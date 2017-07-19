import haxe.Timer;
import jonas.unit.TestCase;

class IntDictTests extends TestCase {
#if benchmark
	@description( 'current implementation benchmark' )
	public function testBenchmark1() {
		var startTime = Timer.stamp();
		var t = new IntDict();
		t.set( 7, 10 );
		while ( t.length < 64 * 1024 ) {
			var len = t.length;
			var k = ( -1212 + 2723 * len ) | 7;
			t.set( k, len );
		}
		trace( 'Current implementation took: ' + ( Timer.stamp() - startTime ) );
		assertTrue(true);
	}
	
	@description( 'reference benchmark' )
	public function testRefBenchmark1() {
		var startTime = Timer.stamp();
		var t = new haxe.ds.IntMap();
		var len = 0;
		t.set( 7, 10 );
		len++;
		while ( len < 64 * 1024 ) {
			var k = ( -1212 + 2723 * len ) | 7;
			t.set( k, len );
			len++;
		}
		trace( 'Std version took: ' + ( Timer.stamp() - startTime ) );
		assertTrue(true);
	}
#else
	@description( '2 keys' )
	public function test2Keys1() {
		var t = new IntDict();
		trace( t );
		assertFalse( t.exists( 0 ) );
		assertEquals( 0, t.length );
		t.set( 0, 10 );
		assertTrue( t.exists( 0 ) );
		assertEquals( 1, t.length );
		assertEquals( 10, t.get( 0 ) );
		assertFalse( t.exists( 7 ) );
		t.set( 7, 10 );
		assertTrue( t.exists( 7 ) );
		assertEquals( 2, t.length );
		assertEquals( 10, t.get( 0 ) );
		assertEquals( 10, t.get( 7 ) );
		trace( t );
	}
	
	@description( 'forced collisions' )
	public function testForcedCollisions1() {
		var startTime = Timer.stamp();
		var t = new IntDict();
		//trace( t );
		assertFalse( t.exists( 7 ) );
		assertEquals( 0, t.length );
		t.set( 7, 10 );
		assertTrue( t.exists( 7 ) );
		assertEquals( 1, t.length );
		assertEquals( 10, t.get( 7 ) );
		while ( t.length < 64 * 1024 ) {
			var len = t.length;
			//trace( len );
			var k = ( -1212 + 2723 * len ) | 7;
			//trace( k );
			assertFalse( t.exists( k ) );
			//trace( t );
			t.set( k, len );
			//trace( t );
			assertTrue( t.exists( k ) );
			assertEquals( len + 1, t.length );
			assertEquals( 10, t.get( 7 ) );
			assertEquals( len, t.get( k ) );
			//trace( t );
		}
		//trace( t );
		//trace( 'Current implementation took: ' + ( Timer.stamp() - startTime ) );
	}
	
	@description( 'unset keys because of cache' )
	public function test2Keys2() {
		var t = new IntDict();
		trace( t );
		assertFalse( t.exists( 0 ) );
		t.set( 7, 10 );
		assertTrue( t.exists( 7 ) );
		assertFalse( t.exists( 15 ) );
		assertEquals( 10, t.get( 7 ) );
		t.set( 15, 100 );
		assertTrue( t.exists( 15 ) );
		assertEquals( 100, t.get( 15 ) );
		assertTrue( t.exists( 7 ) );
		assertEquals( 10, t.get( 7 ) );
		assertTrue( t.exists( 15 ) );
		assertEquals( 100, t.get( 15 ) );
		trace( t );
	}
	
	@description( 'set two different values to the same key, with and without cache' )
	public function testOverwrite1() {
		var t = new IntDict();
		t.set( 0, 1 );
		assertEquals( 1, t.get( 0 ) );
		t.set( 1, 2 );
		assertEquals( 1, t.get( 0 ) );
		assertEquals( 2, t.get( 1 ) );
		t.set( 0, -1 );
		assertEquals( -1, t.get( 0 ) );
		assertEquals( 2, t.get( 1 ) );
		trace( t );
	}
	
	@description( 'insert and then remove some keys (with collisions)' )
	public function testRemove1() {
		var t = new IntDict();
		var k = 7;
		while ( t.length < .6 * 8 ) {
			t.set( k, t.length );
			//trace( t );
			assertEquals( t.length - 1, t.get( k ) );
			k = ( k * 123 * t.length ) | 7;
		}
		trace( t );
		var len = t.length;
		k = 7;
		for ( i in 0...t.length ) {
			t.remove( k );
			assertEquals( --len, t.length, pos_infos( 'length after removal' ) );
			var k2 = 7;
			for ( j in 0...t.length ) {
				if ( j > i ) {
					//trace( k2 );
					//trace( t );
					assertTrue( t.exists( k2 ), pos_infos( 'untouched key still exists' ) );
					//trace( t );
					assertEquals( j, t.get( k2 ), pos_infos( 'untouched key still maps to correct value' ) );
					assertFalse( t.exists( k ), pos_infos( 'deleted key does no exist/cleans cache' ) );
					assertEquals( j, t.get( k2 ), pos_infos( 'untouched key still maps to correct value/with clean cache' ) );
				}
				k2 = ( k2 * 123 * ( j + 1 ) ) | 7;
			}
			k = ( k * 123 * ( i + 1 ) ) | 7;
		}
		trace( t );
	}
	
	@description( 'set/remove/set/reset/remove' )
	public function testRemove2() {
		var t = new IntDict();
		t.set( 0, 10 );
		assertEquals( 1, t.length );
		assertEquals( 10, t.get( 0 ) );
		t.remove( 0 );
		assertEquals( 0, t.length );
		assertFalse( t.exists( 0 ) );
		t.set( 10, 100 );
		assertEquals( 1, t.length );
		assertEquals( 100, t.get( 10 ) );
		t.set( 0, 10 );
		assertEquals( 2, t.length );
		assertEquals( 10, t.get( 0 ) );
		t.remove( 10 );
		assertEquals( 1, t.length );
		assertFalse( t.exists( 10 ) );
		t.remove( 0 );
		assertEquals( 0, t.length );
		assertFalse( t.exists( 0 ) );
		t.set( 0, 10 );
		assertEquals( 1, t.length );
		assertEquals( 10, t.get( 0 ) );
		t.remove( 0 );
		assertEquals( 0, t.length );
		assertFalse( t.exists( 0 ) );
	}
#end
}

