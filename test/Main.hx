import haxe.Log;
import jonas.unit.TestRunner;

class Main {
	static function main() {
#if instrument
		var rawTimers = new Map();
		instrument.TimeCalls.onTimed =
			function (start, finish, ?pos)
			{
				var name = '${pos.className}.${pos.methodName}';
				rawTimers[name] = (rawTimers.exists(name) ? rawTimers[name] : 0.) + finish - start;
			}
#end
		var testRunner = new TestRunner();
		testRunner.customTrace = Log.trace;
		testRunner.add( new IntDictTests() );
		testRunner.run();
#if instrument
		var spent = [for (method in rawTimers.keys()) { method:method, time:rawTimers[method] }];
		spent.sort( function (a,b) return Reflect.compare(b.time, a.time) );
		for (timer in spent) {
			var scale = instrument.TimeCalls.autoScale(timer.time);
			trace('${timer.method}: ${Math.round(timer.time*scale.divisor)} ${scale.symbol}');
		}
#end
	}
}

