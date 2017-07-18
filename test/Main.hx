import haxe.Log;
import jonas.unit.TestRunner;

class Main {
	static function main() {
		var testRunner = new TestRunner();
		testRunner.customTrace = Log.trace;
		testRunner.add( new IntDictTests() );
		testRunner.run();
	}
}

