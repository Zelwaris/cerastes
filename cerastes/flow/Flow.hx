package cerastes.flow;

import game.GameState;
import cerastes.fmt.FlowResource;
import cerastes.data.Nodes;
#if hlimgui
import imgui.NodeEditor;
import imgui.ImGui;
#end

/**
 * Puts text on the screen
 */
 class ConditionNode extends FlowNode
 {
	 @editor("Condition","StringMultiline")
	 public var condition: String;

	 public override function process( runner: FlowRunner )
	 {
		nextAll(runner);
	 }

	 #if hlimgui
	 static final d: NodeDefinition = {
		 name:"Condition",
		 kind: Blueprint,
		 color: 0xFF222288,
		 pins: [
			 {
				 id: 0,
				 kind: Input,
				 label: "\uf04e Input",
				 dataType: Node,
			 },
			 {
				 id: 1,
				 kind: Output,
				 label: "True \uf04b",
				 dataType: Node,
				 color: 0xFF22AA22
			 },
			 {
				 id: 2,
				 kind: Output,
				 label: "False \uf04b",
				 dataType: Node,
				 color: 0xFFaa2222
			 }
		 ]
	 };

	 override function get_def() { return d; }
	 #end
 }


/**
 * Used to switch between scenes
 * be done from other sources.
 */
 @:structInit
 class FlowComment extends FlowNode
 {
	#if hlimgui
	@editor("Comment","String")
	 public var comment: String;
	 public var commentSize: ImVec2 = {x: 0, y: 0};


	 static final d: NodeDefinition = {
		 name:"Comment",
		 kind: Comment,
		 pins: []
	 };

	 override function get_def() { return d; }
	 override function get_label() { return comment; }
	 override function get_size() { return commentSize; }
	 #end
 }



/**
 * Loads (and jumps into) another flow file
 */
class FileNode extends FlowNode
{
	@editor("Label","File","flow")
	public var file: String;

	@noSerialize
	var childRunner: FlowRunner;

	public override function process( runner: FlowRunner )
	{
		childRunner = hxd.Res.loader.loadCache( file, FlowResource ).toFlow();
		childRunner.registerOnExit( this, (handled: Bool) -> { nextAll( runner ); return handled; } );
		childRunner.run();
	}

	#if hlimgui
	static final d: NodeDefinition = {
		name:"File",
		kind: Blueprint,
		color: 0xFF228822,
		pins: [
			{
				id: 0,
				kind: Input,
				label: "\uf04e Input",
				dataType: Node,
			},
			{
				id: 1,
				kind: Output,
				label: "Output \uf04b",
				dataType: Node
			}
		]
	};

	override function get_def() { return d; }
	#end
}


/**
 * Used to switch between scenes
 * be done from other sources.
 */
class SceneNode extends FlowNode
{
	@editor("Scene","ComboString")
	public var scene: String;


	public override function process( runner: FlowRunner )
	{
		Main.currentScene.switchToNewScene( scene );

		super.process(runner);
	}

	#if hlimgui
	static final d: NodeDefinition = {
		name:"Scene",
		kind: Blueprint,
		color: 0xFF228822,
		pins: [
			{
				id: 0,
				kind: Input,
				label: "\uf04e Input",
				dataType: Node,
			},
			{
				id: 1,
				kind: Output,
				label: "Output \uf04b",
				dataType: Node
			}
		]
	};

	override function get_def() { return d; }

	override function getOptions( field: String ): Array<Dynamic>
	{
		if( field == "scene")
		{
			var cls = CompileTime.getAllClasses(Scene);
			return [ for(c in cls) Type.getClassName(c) ];
		}

		return super.getOptions(field);
	}
	#end

}

/**
 * A standard label node. Registers itself with the runner so string-based lookups can
 * be done from other sources.
 */
 @:structInit
class LabelNode extends FlowNode
{
	@editor("Label","String")
	public var labelId: String = null;

	public override function register( runner: FlowRunner )
	{
		runner.labels.set( labelId, this );
	}

	#if hlimgui
	static final d: NodeDefinition = {
		name:"Label",
		kind: Blueprint,
		color: 0xFF882222,
		pins: [
			{
				id: 0,
				kind: Input,
				label: "\uf04e Input",
				dataType: Node,
			},
			{
				id: 1,
				kind: Output,
				label: "Output \uf04b",
				dataType: Node
			}
		]
	};

	override function get_def()	{ return d;	}
	#end
}

/**
 * The entry point for all flow files
 */
 @:structInit
class EntryNode extends FlowNode
{
	public override function register( runner: FlowRunner )
	{
		runner.root = this;
	}

	#if hlimgui
	static final d: NodeDefinition = {
		name:"Entry",
		kind: Blueprint,
		color: 0xFF882222,
		pins: [
			{
				id: 0,
				kind: Output,
				label: "Output \uf04b",
				dataType: Node
			}
		]
	};

	override function get_def()	{ return d;	}
	#end
}

/**
 * The exit point for all flow files, pops stack
 */
 @:structInit
class ExitNode extends FlowNode
{
	public override function process( runner: FlowRunner )
	{
		runner.onExit();
	}

	#if hlimgui
	static final d: NodeDefinition = {
		name:"Entry",
		kind: Blueprint,
		color: 0xFF882222,
		pins: [
			{
				id: 0,
				kind: Input,
				label: "\uf04e Input",
				dataType: Node,
			},
		]
	};

	override function get_def()	{ return d;	}

	#end
}


/**
 * FlowNodes are the base for all nodes in the flow
 *
 * They should never hold state, and instead attach it to the runner when needed. Node
 * sets may be running on multiple runners at once, and may be unloaded/reloaded as files change
 *
 */
@:structInit
class FlowNode extends Node
{
	/**
	 * Basic processing function for nodes. If baseclass is called, will call next
	 * on every pin.
	 *
	 * @param runner
	 */
	public function process( runner: FlowRunner )
	{
		nextAll(runner);
	}

	/**
	 * Calls Next on every pin.
	 *
	 * Safe to call on inputs since they will never hold the sourceId slot
	 *
	 * @param runner
	 */
	public function nextAll( runner: FlowRunner )
	{
		for( portId => pinId in pins )
		{
			next( pinId, runner );
		}
	}

	/**
	 * Process all nodes attached to the specified pin
	 *
	 * pin must always be the source pin
	 *
	 * @param pin
	 * @param runner
	 */
	@:access(cerastes.flow.Flow.FlowRunner)
	public function next( pin: PinId, runner: FlowRunner )
	{
		for( link in runner.links )
		{
			if( link.sourceId == pin )
			{
				var target = runner.lookupNodeByPin( link.destId );
				target.process( runner );
			}
		}
	}


	public function register( runner: FlowRunner )
	{

	}

	#if hlimgui
	function getOptions( field: String ) : Array<Dynamic>
	{
		return null;
	}
	#end

}

@:enum abstract FlowOp(Int) from Int to Int {
	var Invalid = 0;
	var Equ = 1;
	var Gt = 2;
	var Lt = 3;
	var Gte = 4;
	var Lte = 5;
	var Neq = 6;
}

@:structInit
class FlowCondition
{
	public var varA: String = null;
	public var varB: String = null;
	public var constB: Float = 0;
	public var op: FlowOp = Invalid;
}

/**
 * Flow links contain additional data that may control their viability as exits, such as conditions
 */
@:structInit
class FlowLink extends Link
{
	public var conditions: Array<FlowCondition> = null;
}

@:structInit
class FlowFile
{
	public var version: Int = 1;
	public var nodes: Array<FlowNode>;
	public var links: Array<FlowLink>;
}

class FlowContext
{
	public var parser = new hscript.Parser();
	public var interp = new hscript.Interp();

	var runner: FlowRunner;

	public function new( runner: FlowRunner )
	{
		this.runner = runner;

		interp.variables.set("GS", GameState );
		interp.variables.set("Std", Std );

		interp.variables.set("changeScene", changeScene );

		interp.variables.set("set", GameState.set );
		interp.variables.set("get", GameState.get );
		//interp.variables.set("seenNode", seenNode );
	}

	public static function changeScene( className: String )
	{
		#if client
		Main.currentScene.switchToNewScene( className );
		#end
	}
}

@:allow(cerastes.flow.FlowNode)
@:build(cerastes.macros.Callbacks.CallbackGenerator.build())
class FlowRunner
{
	var nodes: Array<FlowNode>;
	var links: Array<FlowLink>;

	var labels: Map<String, FlowNode>;

	var root: FlowNode;
	var stack: List<FlowNode>;

	var res: FlowResource;
	var context: FlowContext;

	/**
	 * OnExit is called when a flow reaches it's exit node.
	 * Mainly used for
	 * @return Bool
	 */
	@:callback
	public function onExit(): Bool;

	public function new( res: FlowResource, ?ctx: FlowContext )
	{
		this.res = res;
		this.nodes = res.getData().nodes;
		this.links = res.getData().links;

		context = ctx == null ? new FlowContext( this ) : ctx;

		for( n in nodes )
			n.register(this);
	}

	public function run()
	{
		root.process(this);
	}

	public function jump( id: String )
	{
		if( !labels.exists(id) )
		{
			Utils.error('Tried to jump to invalid label ${id} in file ${res.name}');
			return;
		}

		var node = labels.get(id);
		node.process( this );


	}

	function lookupNodeByPin( pinId: PinId )
	{
		for( n in nodes )
		{
			for( portId => otherPinId in n.pins )
				if( otherPinId == pinId )
					return n;
		}

		return null;
	}

	public function getOutputs( node: FlowNode, pinId: PinId) : Array<FlowNode>
	{
		var out = [];
		for( l in links )
		{
			if( l.sourceId == pinId )
			{
				out.push( lookupNodeByPin( l.destId ) );
			}
		}

		return out;
	}


}

class Flow
{
	//public static function register
}