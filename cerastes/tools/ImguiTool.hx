
package cerastes.tools;

import hxd.Key;
import hxd.SceneEvents;
#if hlimgui
import cerastes.tools.ImguiTools.IG;
import h3d.Engine;
import h3d.mat.Texture;
import imgui.types.ImFontAtlas.ImFontTexData;
import imgui.ImGui;

import imgui.ImGui.ImFont;
import cerastes.macros.Metrics;
import haxe.rtti.Meta;
import haxe.macro.Expr;

class ImguiTool
{
	public var toolId: Int = 0;
	public var forceFocus: Bool = false;

	public function update( delta: Float ) {}
	public function render( e: h3d.Engine)	{}

	public function destroy() {}

	public function windowID()
	{
		return 'INVALID${toolId}';
	}
}

enum ImGuiPopupType
{
	Info;
	Warning;
	Error;
}

@:structInit
class ImGuiPopup
{
	public var title: String = null;
	public var description: String = null;
	public var type: ImGuiPopupType = Info;

	public var spawnTime: Float = 0;
	public var duration: Float = 5;
}

class ImGuiToolManager
{
	static var tools = new Array<ImguiTool>();

	public static var defaultFont: ImFont;
	public static var headingFont: ImFont;
	public static var consoleFont: ImFont;

	public static var scaleFactor = Utils.getDPIScaleFactor();

	public static var toolIdx = 0;

	public static var popupStack: Array<ImGuiPopup> = [];

	public static function showPopup( title: String, desc: String, type: ImGuiPopupType )
	{
		popupStack.push({
			title: title,
			description: desc,
			type: type,
			spawnTime: Sys.time()
		});
	}

	public static function showTool( cls: String )
	{
		var type = Type.resolveClass( "cerastes.tools." + cls);
		Utils.assert( type != null, 'Trying to create unknown tool cerastes.tools.${cls}');


		if(Meta.getType(type).multiInstance == null )
		{
			for( t in tools )
			{
				if( Std.isOfType( t, type ) )
					return t;
			}
		}


		var t : ImguiTool = Type.createInstance(type, []);

		t.toolId = toolIdx++;

		tools.push(t);

		return t;
	}

	public static function closeTool( t: ImguiTool )
	{
		t.destroy();
		tools.remove(t);
	}

	public static function init()
	{
		ImGui.setConfigFlags( DockingEnable );

		var dpiScale = Utils.getDPIScaleFactor();
		if( dpiScale > 1 )
		{
			var style: ImGuiStyle = ImGui.getStyle();
			style.scaleAllSizes( dpiScale );
		}

		// Default font
		ImGuiToolManager.defaultFont = ImGuiToolManager.addFont("res/tools/Ruda-Bold.ttf", 14, true);
		ImGuiToolManager.headingFont = ImGuiToolManager.addFont("res/tools/Ruda-Bold.ttf", 21, true);
		ImGuiToolManager.consoleFont = ImGuiToolManager.defaultFont; //ImGuiToolManager.addFont("res/tools/console.ttf", 14);
		ImGuiToolManager.buildFonts();


	}

	public static function update( delta: Float )
	{
		Metrics.begin();

		// Make sure there aren't any tool ID collisions
		var toolMap: Map<String, ImguiTool> = [];
		var toolCopy = tools.copy();
		for( i in 0 ... toolCopy.length )
		{
			var tool = toolCopy[i];
			if( toolMap.exists( tool.windowID() ) )
			{
				toolMap.get(tool.windowID()).forceFocus = true;
				tools.remove(tool);
				continue;
			}

			toolMap.set(tool.windowID(), tool);
			tool.update( delta );
		}

		var offset: Float = 0;

		var i = popupStack.length;
		while( i-- > 0 )
		{
			var popup = popupStack[i];
			if( popup.spawnTime + popup.duration < Sys.time() )
			{
				popupStack.splice(i,1);
				i--;
			}

			offset = renderPopup( popup, i, offset );
		}


		Metrics.end();
	}

	public static function renderPopup( popup: ImGuiPopup, idx: Int, offset: Float )
	{
		var windowFlags = ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.AlwaysAutoResize | ImGuiWindowFlags.NoSavedSettings | ImGuiWindowFlags.NoFocusOnAppearing | ImGuiWindowFlags.NoNav;

		var padding: Float = 10 * scaleFactor;
		var height: Float = 0;

		ImGui.setNextWindowBgAlpha(0.350); // Transparent background
		ImGui.setNextWindowPos({x: 10, y: 50 + offset }, ImGuiCond.Always);
		//ImGui.setNextWindowSize(null, ImGuiCond.Always);
		if (ImGui.begin('${popup.title}##${idx}', null, windowFlags))
		{
			ImGui.pushTextWrapPos( 200 * scaleFactor );
			switch( popup.type )
			{
				case Info:
					ImGui.pushFont( headingFont );
					ImGui.text( '\uf05a ${popup.title}');
					ImGui.popFont();

				case Warning:
					ImGui.pushFont( headingFont );
					ImGui.textColored( {x: 1.0, y: 1.0, z: 0, w: 1.0}, '\uf071 ${popup.title}');
					ImGui.popFont();

				case Error:
					ImGui.pushFont( headingFont );
					ImGui.textColored( {x: 1.0, y: 0, z: 0, w: 1.0}, '\uf1e2 ${popup.title}');
					ImGui.popFont();
			}

			ImGui.separator();
			ImGui.dummy({x:10,y:5 * scaleFactor});
			ImGui.text(popup.description);
			height = ImGui.getWindowHeight();

			ImGui.popTextWrapPos();

		}

		ImGui.end();



		return offset + height + padding;
	}

	public static function render( e: h3d.Engine )
	{
		Metrics.begin();
		for( t in tools )
			t.render( e );
		Metrics.end();
	}

	public static function addFont( file: String, size: Float, includeGlyphs: Bool = false )
	{
		var dpiScale = Utils.getDPIScaleFactor();
		Utils.info('Add font: ${file} ${size*dpiScale}px');

		var atlas = ImGui.getFontAtlas();
		//atlas.addFontDefault();
		var font = atlas.addFontFromFileTTF(file, size * dpiScale);


		var facfg = new ImFontConfig();

		#if imjp
		var ranges = new hl.NativeArray<hl.UI16>(11);
		// fa
		ranges[0] = 0xf000;
		ranges[1] = 0xf6ff;
		// hira
		ranges[2] = 0x3040;
		ranges[3] = 0x309f;
		// kata
		ranges[4] = 0x30A0;
		ranges[5] = 0x30FF;
		// Half
		ranges[6] = 0xFF00;
		ranges[7] = 0xFFEF;
		// CJK
		ranges[8] = 0x4e00;
		ranges[9] = 0x9FAF;
		ranges[10] = 0;

		var jpcfg = new ImFontConfig();
		jpcfg.MergeMode = true;
		#else
		var ranges = new hl.NativeArray<hl.UI16>(3);
		// fa
		ranges[0] = 0xf000;
		ranges[1] = 0xf6ff;
		ranges[2] = 0;
		#end

		#if imjp
		atlas.addFontFromFileTTF("res/tools/NotoSansJP-Regular.otf",  size * dpiScale, jpcfg, ranges);
		#end

		if( includeGlyphs )
		{
			facfg.MergeMode = true;
			facfg.GlyphMinAdvanceX = 18 * dpiScale;
			atlas.addFontFromFileTTF("res/tools/fa-regular-400.ttf",  size * dpiScale * 0.8, facfg, ranges);
			atlas.addFontFromFileTTF("res/tools/fa-solid-900.ttf",  size * dpiScale * 0.8, facfg, ranges);
		}
		atlas.build();

		return font;
	}

	public static function buildFonts()
	{
		var fontInfo: ImFontTexData = new ImFontTexData();
		var atlas = ImGui.getFontAtlas();
		atlas.getTexDataAsRGBA32( fontInfo );

		// create font texture
		var textureSize = fontInfo.width * fontInfo.height * 4;
		var fontTexture = Texture.fromPixels(new hxd.Pixels(
			fontInfo.width,
			fontInfo.height,
			fontInfo.buffer.toBytes(textureSize),
			hxd.PixelFormat.RGBA));

		atlas.setTexId( fontTexture );
		Utils.info('Font atlas built: ${fontInfo.width}x${fontInfo.height}');
	}


	public static function updatePreviewEvents( startPos: ImVec2, previewEvents: SceneEvents )
	{
		#if hlimgui
		var hovered = ImGui.isItemHovered();

		//InputManager.enabled = hovered;
		if( !hovered )
			return;

		var endPos: ImVec2 = ImGui.getCursorScreenPos();
		var mousePos: ImVec2 = ImGui.getMousePos();

		var height = endPos.y - startPos.y ;

		var mouseScenePos = {x: ( mousePos.x - endPos.x), y: ( mousePos.y - endPos.y + height ) };

		// rescale to engine size

		var viewportDimensions = IG.getViewportDimensions();
		var viewportWidth = viewportDimensions.width;
		var viewportHeight = viewportDimensions.height;

		var engine = Engine.getCurrent();
		var sx: Single = engine.width / viewportWidth;
		var sy: Single = engine.height / viewportHeight;
		mouseScenePos.x *= sx;
		mouseScenePos.y *= sy;

		var event = new hxd.Event(EMove, mouseScenePos.x, mouseScenePos.y);

		if( ImGui.isMouseClicked( ImGuiMouseButton.Left ) )
		{
			event.kind = EPush;
			event.button = 0;
		}
		else if( ImGui.isMouseClicked( ImGuiMouseButton.Right ) )
		{
			event.kind = EPush;
			event.button = 1;
		}
		else if( ImGui.isMouseReleased( ImGuiMouseButton.Left ) )
		{
			event.kind = ERelease;
			event.button = 0;
		}
		else if( ImGui.isMouseReleased( ImGuiMouseButton.Right ) )
		{
			event.kind = ERelease;
			event.button = 1;
		}
		if( Key.isPressed( Key.MOUSE_WHEEL_DOWN ) )
		{
			event.kind = EWheel;
			event.wheelDelta = -1;
		}
		else if( Key.isPressed( Key.MOUSE_WHEEL_UP ) )
		{
			event.kind = EWheel;
			event.wheelDelta = 1;
		}


		@:privateAccess previewEvents.emitEvent( event );

		//preview.dispatchListeners( event );

		#end
	}
}

#end