package ;

import jonas.RevIntIterator;

/*
 * Open addressing hash table
 * Copyright (c) 2012,2017 Jonas Malaco Filho
 * Licensed under the MIT license. Check LICENSE.txt for more information.
 */
class IntDict<T> {
/*
 * Some notes on IntDict:
 *
 * This is obviously NOT threadsafe (because of caches). Also, during any iteration, the only safe
 * updating operation is remove (since it won't shrink the table). Set can trigger growth or shrinkage
 * and completely change the whole table. Even set on existing keys can still trigger shrinkage.
 *
 * The collsion resolving is done though open addressing.
 *
 * An Integer is its own hash value.
 *
 * State, key and value are stored in separe arrays. This is more economical (less memory consumption
 * or calls to new) but has bad cache locality.
 *
 * An entry [i] in the table may be in one of the following states:
 *   - FILLED: the entry exists
 *   - FREE: the entry does not exist and no further probing is necessary
 *   - DUMMY: there was something here, should keep probing
 *
 * The cache can be in one of the following states:
 *   - FILLED: the key exists; safe for set/remove
 *   - FREE: the key does not exists, AND the cache index points to the first lookup index;
 *           safe for set/remove
 *   - DUMMY: the key does not exists, but nothing else is sure; UNSAFE for set/remove
 *
 * There also is another state (BAD) used by probeCount(debug only) and cache.
 * Both cache and probeCount should be ignored if on state==BAD.
 */

	// definitions
	static inline var FILLED = 0;
	static inline var FREE = 3;
	static inline var DUMMY = 1;
	static inline var BAD = 2;
	static inline var START_SIZE = 8;
	// static inline var PROBE_A = 5; // from Python 3.2.3 (doc/dictobject.c::93)
	// static inline var PROBE_B = 2; // from Python 3.2.3 (doc/dictobject.c::357)
	// static inline var PERTURB_SHIFT = 5; // from Python
	static inline var GROWTH_SHIFT = 1; // 2**GROWTH_SHIFT = 2
	static inline var GROWTH_SHIFT_SMALL = 2; // 2**GROWTH_SHIFT = 4
	static inline var GROWTH_SMALL = 8192;
	static inline var SHRINKAGE_SMALL = GROWTH_SMALL << ( GROWTH_SHIFT_SMALL - GROWTH_SHIFT );
	static inline var MAX_LOAD_FACTOR = .7; // 2/3, as in Python, but rounded up
	static inline var MIN_LOAD_FACTOR = MAX_LOAD_FACTOR / ( 1 << GROWTH_SHIFT );
	static inline var MIN_LOAD_FACTOR_SMALL = MAX_LOAD_FACTOR / ( 1 << GROWTH_SHIFT_SMALL ) - .05;

	// structural fields & state
	var ks : KeyStateTable; // key–state table
	var v : haxe.ds.Vector<T>; // value table
	var size : Int; // table size; while resizing, this is set to BAD to avoid shrinkage
	var mask : Int; // size - 1, or mask for optimizing x mod size = x & ( size - 1 )
	public var length( default, null ) : Int;

	// probing shared info
	var j : Int; // current index, in range [0,size-1]
	var perturb : Int; // hash based perturbation, always positive

	// cache (regarding current j value)
	var cachedKey : Int;
	var cachedState : Int;

	// debug information
	#if debug
	public var probeCount( default, null ) : Int;
	#end

	public function new() {
		alloc( START_SIZE );
		#if debug
		probeCount = BAD;
		#end
	}

// ---- Public API

	public inline function loadFactor() : Float {
		return length / size;
	}

	public function iterator() : Iterator<T> {
		var i = 0;
		return {
			hasNext : function() {
				for ( j in i...size )
					if ( ks.getState(j) == FILLED ) {
						i = j;
						return true;
					}
				return false;
			},
			next : function() {
				return v[i++];
			}
		};
	}

	public function keys() : Iterator<Int> {
		var i = 0;
		return {
			hasNext : function() {
				for ( j in i...size )
					if ( ks.getState(j) == FILLED ) {
						i = j;
						return true;
					}
				return false;
			},
			next : function() {
				return ks.getKey(i++);
			}
		};
	}

	public function toString() : String {
		var b = new StringBuf();
		b.add( '{ ' );
		var f = true;
		for ( k in keys() ) {
			if ( f )
				f = false;
			else
				b.add( ', ' );
			b.add( k );
			b.add( ' => ' );
			b.add( get( k ) );
		}
		b.add( ' }' );
		#if debug
		b.add( ' : loadFactor=' );
		b.add( loadFactor() );
		b.add( ', length=' );
		b.add( length );
		b.add( ', size=' );
		b.add( size );
		b.add( ', cachedState=' );
		b.add( switch ( cachedState ) {
			case FILLED : 'filled';
			case FREE : 'free';
			case DUMMY : 'dummy';
			case BAD : 'bad';
		} );
		b.add( ', cachedIndex=' );
		b.add( j );
		b.add( ', cachedKey=' );
		b.add( cachedKey );
		b.add( ', lastProbeCount=' );
		b.add( probeCount );
		#end
		return b.toString();
	}

	// check if key exists in the dictionary
	public function exists( key : Int ) : Bool {

		// attempt to fetch the answer from the cache
		// if the cache is not BAD and the cache key matches the input,
		// than the cache state will be one of the folling, depending if the key:
		//   - exists: FILLED
		//   - does not exist and is safe to use the cached index: FREE
		//   - just does not exists: DUMMY (unsafe)
		// therefore, the key exists in the dictionary if cachedState==FILLED
		if ( cachedState != BAD && cachedKey == key ) {
			#if debug
			probeCount = -1;
			#end
			return cachedState == FILLED;
		}

		#if debug
		probeCount = 0;
		#end

		// start to lookup the table
		// start on index = hash mod size
		j = mod( key ); // Int hashes to itself
		// if that slot contains a valid key-value pair, test the key
		// if the key matches the input, update the cache and return true (found)
		if ( ks.getState(j) == FILLED && ks.getKey(j) == key ) {
			cachedKey = key;
			cachedState = FILLED;
			return true;
		}

		// if the slot is marked as free, can stop, update the cache and return false (not found)
		if ( ks.getState(j) == FREE ) {
			cachedKey = key;
			cachedState = FREE;
			return false;
		}

		// did not find the key in the initial index
		// will execute the probing sequence
		// but first, prepare the perturbation
		perturbInit( key );

		// begin probing
		// get the first new index
		probe();
		var sj = ks.getState(j); // s[j] cache
		// go over the probing sequence returned indices
		// if a slot is free, return false
		// else
		//     if the key-value pair exists, check the key and if, it matches, return true
		//     (updating the cache)
		//     else, get the next index
		while ( sj != FREE ) {
			if ( sj == FILLED && ks.getKey(j) == key ) {
				cachedKey = key;
				cachedState = FILLED;
				return true;
			}
			probe();
			sj = ks.getState(j);
		}

		// did not find anything
		cachedKey = key;
		cachedState = DUMMY;
		return false;
	}

	// get value for key
	// if the key does not exists, returns cast null
	// should always use exists( k ) before get( k ) if there is no garantee that
	// the k exists in the dictionary; using so will NOT result in two lookups
	public function get( key : Int ) : T {

		// attempt to fetch the answer from the cache
		// if the cache is not BAD and the cache key matches the input,
		// than the cache state will be one of the folling, depending if the key:
		//   - exists: FILLED
		//   - does not exist and is safe to use the cached index: FREE
		//   - just does not exists: DUMMY (unsafe)
		// therefore, the key exists in the dictionary if cachedState==FILLED
		if ( cachedState != BAD && cachedKey == key ) {
			#if debug
			probeCount = -1;
			#end
			if ( cachedState == FILLED )
				return v[j];
			else
				#if neko
				return null;
				#else
				return cast null;
				#end
		}

		#if debug
		probeCount = 0;
		#end

		// start to lookup the table
		// start on index = hash mod size
		j = mod( key ); // Int hashes to itself
		// if that slot contains a valid key-value pair, test the key
		// if the key matches the input, update the cache and return the value (found)
		if ( ks.getState(j) == FILLED && ks.getKey(j) == key ) {
			cachedKey = key;
			cachedState = FILLED;
			return v[j];
		}

		// if the slot is marked as free, can stop, update the cache and return null (not found)
		if ( ks.getState(j) == FREE ) {
			cachedKey = key;
			cachedState = FREE;
			#if neko
			return null;
			#else
			return cast null;
			#end
		}

		// did not find the key in the initial index
		// will execute the probing sequence
		// but first, prepare the perturbation
		perturbInit( key );

		// begin probing
		// get the first new index
		probe();
		var sj = ks.getState(j); // s[j] cache
		// go over the probing sequence returned indices
		// if a slot is free, return false
		// else
		//     if the key-value pair exists, check the key and if, it matches, return true
		//     (updating the cache)
		//     else, get the next index
		while ( sj != FREE ) {
			if ( sj == FILLED && ks.getKey(j) == key ) {
				cachedKey = key;
				cachedState = FILLED;
				return v[j];
			}
			probe();
			sj = ks.getState(j);
		}

		// did not find anything
		cachedKey = key;
		cachedState = DUMMY;
		#if neko
		return null;
		#else
		return cast null;
		#end
	}

	// set value corresponding to key
	// if the key already exists, it's value is replaced
	// returns the same value
	public function set( key : Int, value : T ) : T {

		// check if the cache has usefull information
		// if the cache is not BAD and the cache key matches the input,
		// than the cache state will be one of the folling, depending if the key:
		//   - exists: FILLED
		//   - does not exist and is safe to use the cached index: FREE
		//   - just does not exists: DUMMY (unsafe)
		if ( ( cachedState == FILLED || cachedState == FREE ) && cachedKey == key ) {
			#if debug
			probeCount = -1;
			#end
			// if the key is not being replaced, increment length
			if ( cachedState != FILLED )
				length++;
			ks.setState(j, FILLED);
			ks.setKey(j, key);
			v[j] = value;
			cachedState = FILLED;
			return value;
		}

		#if debug
		probeCount = 0;
		#end

		// not on cache, start doing table lookups
		// first index
		j = mod( key );
		var sj;
		// probe until a FREE, DUMMY or equal key is found
		if (ks.getState(j) == FILLED && ks.getKey(j) != key) {
			// initial perturbation
			perturbInit( key );
			do {
				probe();
			} while (ks.getState(j) == FILLED && ks.getKey(j) != key);
		}
		// if the key is not being replaced, increment length
		if ( ks.getState(j) != FILLED )
			length++;
		ks.setState(j, FILLED);
		ks.setKey(j, key);
		v[j] = value;
		cachedKey = key;
		cachedState = FILLED;
		resizeIfNeeded();
		return value;
	}

	// remove key from the dictionary
	// it consists in setting the slot to DUMMY
	// will not shrink the table (that is only possible on set)
	public function remove( key : Int ) : Bool {

		// attempt to use the cache
		// if the cache is not BAD and the cache key matches the input,
		// than the cache state will be one of the folling, depending if the key:
		//   - exists: FILLED
		//   - does not exist and is safe to use the cached index: FREE
		//   - just does not exists: DUMMY (unsafe)
		// therefore, the key exists in the dictionary if cachedState==FILLED
		if ( cachedState != BAD && cachedKey == key ) {
			#if debug
			probeCount = -1;
			#end
			if ( cachedState == FILLED ) {
				ks.setState(j, DUMMY);
				cachedState = DUMMY;
				length--;
				return true;
			}
			else
				return false;
		}

		#if debug
		probeCount = 0;
		#end

		// start to lookup the table
		// start on index = hash mod size
		j = mod( key ); // Int hashes to itself
		// if that slot contains a valid key-value pair, test the key
		// if the key matches the input, remove it
		if ( ks.getState(j) == FILLED && ks.getKey(j) == key ) {
			ks.setState(j, DUMMY);
			cachedKey = key;
			cachedState = DUMMY;
			length--;
			return true;
		}

		// if the slot is marked as free, can stop, update the cache and return false (not removed)
		if ( ks.getState(j) == FREE ) {
			cachedKey = key;
			cachedState = FREE;
			return false;
		}

		// did not find the key in the initial index
		// will execute the probing sequence
		// but first, prepare the perturbation
		perturbInit( key );

		// begin probing
		// get the first new index
		probe();
		var sj = ks.getState(j); // s[j] cache
		// go over the probing sequence returned indices
		// if a slot is free, return false
		// else
		//     if the key-value pair exists, check the key and if, it matches, remove it
		//     else, get the next index
		while ( sj != FREE ) {
			if ( sj == FILLED && ks.getKey(j) == key ) {
				ks.setState(j, DUMMY);
				cachedKey = key;
				cachedState = DUMMY;
				length--;
				return true;
			}
			probe();
			sj = ks.getState(j);
		}

		// did not find anything
		cachedKey = key;
		cachedState = DUMMY;
		return false;
	}

// ---- Helper API

	inline function mod( x : Int ) : Int {
		return x & mask;
	}

	inline function alloc( m : Int ) {
		ks = new KeyStateTable(m);
		v = new haxe.ds.Vector(m);
		ks.reset(FREE);
		mask = m - 1;
		size = m;
		length = 0;
		clearCache();
	}

	inline function perturbInit( hash : Int ) {
	}

	inline function probe() {
		#if debug
		probeCount++;
		#end
		j = mod(j + 1);
	}

	inline function clearCache() {
		cachedState = BAD;
	}

	inline function resizeIfNeeded() {
		var alpha = loadFactor();
		//trace( [ length, size, Std.int( alpha * 100 ) ] );
		if ( alpha > MAX_LOAD_FACTOR ) {
			//trace( [ length, size, Std.int( alpha * 100 ) ] );
			doResize( size << ( length <= GROWTH_SMALL ? GROWTH_SHIFT_SMALL : GROWTH_SHIFT ) );
		}
		else if ( size > 8 )
			if ( length <= SHRINKAGE_SMALL && alpha < MIN_LOAD_FACTOR_SMALL ) {
				//trace( [ length, size, Std.int( alpha * 100 ) ] );
				doResize( size >> GROWTH_SHIFT ); // when shrinking, always use the default GROWTH_SHIFT
			}
			else if ( length > SHRINKAGE_SMALL && alpha < MIN_LOAD_FACTOR ) {
				//trace( [ length, size, Std.int( alpha * 100 ) ] );
				doResize( size >> GROWTH_SHIFT );
			}
	}

	function doResize( m : Int ) {
		// backup the current table
		var bks = ks;
		var bv = v;
		var bsize = size;
		var blength = length;
		// alloc the new table
		alloc( m );
		// and reinsert
		for ( i in 0...bsize ) {
			if ( bks.getState(i) == FILLED ) {
				var key = bks.getKey(i);
				var value = bv[i];
				// the following has been inlined and optimized from set
				j = mod(key);
				if (ks.getState(j) == FILLED && ks.getKey(j) != key) {
					perturbInit( key );
					do {
						probe();
					} while (ks.getState(j) == FILLED && ks.getKey(j) != key);
				}
				ks.setState(j, FILLED);
				ks.setKey(j, key);
				v[j] = value;
			}
		}
		// clean the cache
		clearCache();
		// restore length and update size
		length = blength;
		size = m;
	}
}

/*
	 STATE KEY KEY KEY ... KEY KEY KEY STATE KEY ...

	 State:

	 0-15: 0
	 16-31: 17
	 32-47: 34
	 48-63: 51
	 64-75: 68
*/
abstract KeyStateTable(haxe.ds.Vector<Int>) {
	inline public function new(size)
	{
		var stateSize = ((size - 1) >> 4) + 1;
		this = new haxe.ds.Vector(size + stateSize);
	}

	inline public function reset(value:Int):Int
	{
		var fill = value;
		for (pos in 1...16)
			fill |= value << (pos << 1);
		var i = 0;
		do {
			this[i] = fill;
			i += 17;
		} while(i < this.length);
		return value;
	}

	inline public function getState(index:Int):Int
	{
		var bucket = index >> 4;
		var word = (bucket << 4) + bucket;
		var offset = (index & 15) << 1;
		return (this[word] & (3 << offset)) >> offset;
	}

	inline public function setState(index:Int, value:Int):Int
	{
		var bucket = index >> 4;
		var word = (bucket << 4) + bucket;
		var offset = (index & 15) << 1;
		var clean = -1 ^ (3 << offset);
		this[word] = (this[word] & clean) | (value << offset);
		return value;
	}

	inline public function getKey(index:Int):Int
	{
		var bucket = index >> 4;
		return this[index + bucket + 1];
	}

	inline public function setKey(index:Int, value:Int):Int
	{
		var bucket = index >> 4;
		return this[index + bucket + 1] = value;
	}
}

