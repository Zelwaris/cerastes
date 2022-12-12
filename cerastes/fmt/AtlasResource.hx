package cerastes.fmt;

import sys.thread.Mutex;
import cerastes.tools.ImguiTool.ImGuiToolManager;
import sys.thread.Lock;
import sys.thread.Thread;
import h2d.Tile;
import cerastes.file.CDParser;
import cerastes.file.CDPrinter;
import hxd.Pixels;
import cerastes.c2d.Vec2;
import hxd.res.Resource;

enum PackMode {
	MaxRects;
	Guillotine;
	Shelf;
	Skyline;
}

@:structInit class Vec2i
{
	public var x: Int = 0;
	public var y: Int = 0;
}

@:structInit class Vec4i
{
	public var x: Int = 0;
	public var y: Int = 0;
	public var z: Int = 0;
	public var w: Int = 0;

}

@:structInit class PackJob
{
	public var xs: Int = 0;
	public var ys: Int = 0;
	public var mode: PackMode = MaxRects;
}


@:structInit class AtlasFrame
{
	public var file: String = null;

	@serializeType("cerastes.fmt.Vec2i")
	public var pos: Vec2i = {};
	@serializeType("cerastes.fmt.Vec2i")
	public var offset: Vec2i = {};
	@serializeType("cerastes.fmt.Vec2i")
	public var size: Vec2i = {};

	@noSerialize
	public var atlas: Atlas = null;

	@noSerialize
	public var tile(get, never): h2d.Tile;

	public function get_tile()
	{
		atlas.ensureLoaded();
		return @:privateAccess atlas.tile.sub( pos.x, pos.y, size.x, size.y, offset.x, offset.y );
	}
}

@:structInit class AtlasEntry
{
	//public var name: String = null;
	@serializeType("cerastes.fmt.AtlasFrame")
	public var frames: Array<AtlasFrame> = [];
	@serializeType("cerastes.fmt.Vec2i")
	public var size: Vec2i = {};
	@serializeType("cerastes.fmt.Vec2i")
	public var bbox: Vec4i = {};
	@serializeType("cerastes.fmt.Vec2i")
	public var origin: Vec2i = {};

	//

	@noSerialize
	public var name: String = null;
	@noSerialize
	public var atlas: Atlas = null;

	@noSerialize
	public var tile(get, never): h2d.Tile;

	public function get_tile()
	{
		atlas.ensureLoaded();
		return @:privateAccess atlas.tile.sub( frames[0].pos.x, frames[0].pos.y, frames[0].size.x, frames[0].size.y, frames[0].offset.x, frames[0].offset.y );
	}
}

@:structInit class Atlas
{
	@serializeType("cerastes.fmt.AtlasEntry")
	public var entries: Map<String,AtlasEntry> = [];
	public var textureFile: String = null;

	public var packMode: PackMode = MaxRects;
	public var size: Vec2i = {};

	@noSerialize
	var tile: Tile = null;

	public function load()
	{
		for( name => entry in entries )
		{
			entry.name = name;
			entry.atlas = this;

			for( f in entry.frames )
				f.atlas = this;
		}
	}

	public function ensureLoaded()
	{
		if( tile == null )
			tile = hxd.Res.loader.load( textureFile ).toTile();
	}

	#if binpacking
	#if tools
	@noSerialize var jobWorkerThread: Thread = null;
	@noSerialize var trimWork: Array<AtlasEntry> = [];
	@noSerialize var pool: Array<Thread> = null;
	@noSerialize var binSizes = [32,64,128,256,512,1024,2048,4096,8192];
	@noSerialize var fileName: String;
	@noSerialize var workerLock = new Lock();
	@noSerialize var packJobs: Array<PackJob> = [];
	@noSerialize var trimMutex = new Mutex();


	public function pack( file: String )
	{
		//jobWorkerThread = Thread.create(jobWorker);
		fileName = file;
		jobWorker();


	}


	function jobWorker()
	{
		if( pool != null )
			return;

		trimWork = [];
		pool = [];
		binSizes = [32,64,128,256,512,1024,2048,4096,8192];
		trimMutex = new Mutex();
		workerLock = new Lock();

		for( key => entry in entries )
		{
			trimWork.push( entry );
		}

		// Create a thread pool
		var cores = Utils.getCoreCount();
		for( i in 0 ... cores )
		{
			pool.push( Thread.create( trimWorker ) );
		}


		for( i in 0 ... cores )
			workerLock.wait();

		Utils.assert(trimWork.length == 0, "Not all threads are ready");

		// Actually pack
		var xsIdx = 0;
		var ysIdx = 0;




		var minX = 0;
		var minY = 0;

		var packed = false;
		var occupancy = 0.0;
		do
		{
			var fit = 0;
			var packer = new binpacking.MaxRectsPacker( binSizes[xsIdx], binSizes[ysIdx], false );
			packed = true;

			// @todo: Sort entries by size descending. Should produce better pack results!
			for( entry in entries )
			{

				for( frame in entry.frames )
				{
					if( frame.size.x == 0 && frame.size.y == 0 )
						continue;

					var heuristic = binpacking.MaxRectsPacker.FreeRectChoiceHeuristic.BestShortSideFit;
					var rect = packer.insert( frame.size.x, frame.size.y, heuristic ) ;
					if( rect == null )
					{
						packed = false;
						if( xsIdx < ysIdx )
							xsIdx++;
						else
							ysIdx++;

						if( xsIdx >= binSizes.length || ysIdx >= binSizes.length )
						{
							Utils.error('Cannot fit rects inside max page size of ${binSizes[xsIdx]}x${binSizes[ysIdx-1]} (Fit ${fit})');
							return;
						}
						break;
					}

					frame.pos.x = Math.floor( rect.x );
					frame.pos.y = Math.floor( rect.y );
					fit++;
				}

				if( !packed )
					break;

			}

			occupancy = packer.occupancy();
		}
		while( !packed );

		// Build the actual texture
		var pixels = Pixels.alloc(binSizes[xsIdx], binSizes[ysIdx], hxd.PixelFormat.ARGB);

		for( entry in entries )
		{
			for( frame in entry.frames )
			{
				var i = hxd.Res.loader.load( frame.file ).toImage();
				var p = i.getPixels();
				var size = i.getSize();
				pixels.blit(frame.pos.x, frame.pos.y, p, frame.offset.x, frame.offset.y, frame.size.x, frame.size.y );
			}
		}

		// Write result
		var texFile = StringTools.replace(fileName,".catlas","_tex.png");
		var bytes = pixels.toPNG();
		textureFile = texFile;
		sys.io.File.saveBytes( 'res/${textureFile}', bytes);
		sys.io.File.saveContent( 'res/${fileName}', CDPrinter.print( this ) );

		#if hlimgui
		ImGuiToolManager.showPopup('Packing complete','Packed size: ${binSizes[xsIdx]}x${binSizes[ysIdx]}, occupancy ${Math.round( occupancy * 100 )}%', Info);
		#end

		pool = null;

	}

	function trimWorker()
	{
		while( true )
		{
			trimMutex.acquire();
			var entry = trimWork.shift();
			trimMutex.release();
			if( entry == null )
				break;


			trimEntry( entry );



		}

		workerLock.release();
	}

	function trimEntry( entry: AtlasEntry )
	{
		for( frame in entry.frames )
		{
			var i = hxd.Res.loader.load( frame.file ).toImage();

			var p = i.getPixels();

			frame.size.x = p.width;
			frame.size.y = p.height;
			frame.offset.x = 0;
			frame.offset.y = 0;

			if( p.format != BGRA )
			{
				trace( p.format );
				continue;
			}

			// trim X
			var trimLeft = 0;
			var trimRight = 0;
			var left = true;
			for(x in 0 ... p.width )
			{
				var clear = true;
				for( y in 0 ... p.height )
				{
					if( p.getPixel(x,y) & 0xFF000000 != 0 )
					{
						left = false;
						clear = false;
						trimRight = 0;
						break;
					}
				}

				if( !clear )
					continue;

				if( left )
					trimLeft++;
				else
					trimRight++;
			}

			if( trimLeft > 0 || trimRight > 0 )
			{
				//trace('Trimmed ${trimLeft + trimRight}/${p.width} pixels off y in ${frame.file}');
				frame.offset.x += trimLeft;
				frame.size.x -= trimLeft + trimRight;

			}

			// trim Y
			var trimTop = 0;
			var trimBottom = 0;
			var top = true;
			for(y in 0 ... p.height )
			{
				var clear = true;
				for( x in 0 ... p.width )
				{
					if( p.getPixel(x,y) & 0xFF000000 != 0 )
					{
						top = false;
						clear = false;
						trimBottom = 0;
						break;
					}
				}

				if( !clear )
					continue;

				if( top )
					trimTop++;
				else
					trimBottom++;
			}

			if( trimTop > 0 || trimBottom > 0 )
			{
				//trace('Trimmed ${trimTop + trimBottom}/${p.height} pixels off y in ${frame.file}');
				frame.offset.y += trimTop;
				frame.size.y -= trimTop + trimBottom;
			}
		}
	}

	#end
	#end
}


class AtlasResource extends Resource
{
	var data: Atlas;

	static var minVersion = 1;
	static var version = 1;

	public function getTile( t: String )
	{
		getData();

	}

	public function getData( ?cache: Bool = true ) : Atlas
	{
		if (data != null && cache) return data;

		data = CDParser.parse( entry.getText(), Atlas );
		data.load();
		return data;
	}
}