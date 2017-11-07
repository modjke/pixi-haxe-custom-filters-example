package filters.custom ;
import pixi.core.renderers.webgl.utils.RenderTarget;
import haxe.io.Float32Array;
import js.Browser;
import pixi.core.graphics.Graphics;
import pixi.core.math.Matrix;
import pixi.core.math.shapes.Rectangle;
import pixi.core.renderers.webgl.filters.Filter;
import pixi.core.renderers.webgl.managers.FilterManager;
import pixi.core.sprites.Sprite;
import pixi.core.text.Text;
import pixi.interaction.InteractionEvent;
import pixi.plugins.app.Application;

using StringTools;

class Main extends Application
{

	public static function main()
	{
		new Main();
	}
	
	static inline var GRID_WIDTH = 200;
	static inline var GRID_HEIGHT = 60;
	static inline var GAP = 40;
	
	var exampleTop:Float = GAP;
	var exampleLeft:Float = GAP;
	
	var filterWithUniforms:FilterWithUniforms;
	
	function new()
	{
		super();
		
		//default setup
		position = Application.POSITION_FIXED;
		autoResize = true;
		onUpdate = update;
		super.start();
		stage.interactive = true;
		
		// basic examples
		
		// original image (or graphic), no filters applied
		addExample("original", []);
		// color filter that multiplies rgba values of each pixel by 0.5		
		addExample("color * 0.5", [new BasicFilter('
			color *= 0.5;
		')]);
		// invert rgb value of each pixel (alpha is untouched)
		addExample("1.0 - color.rgb (invert)", [new BasicFilter('
			color.rgb = vec3(1.0) - color.rgb;
		')]);
		// demonstrate texture coordinates (x -> red, y -> green, 1.0 -> blue, 1.0 -> alpha)
		// notice how bottom right corner is NOT white
		// that means that vTextureCoord is not mapped 0.0...1.0 to a filtered sprite
		// also toggle that example on/off and you will see that filter area is bigger than the actual size of a rendered graphic (or sprite)
		// this happens becouse filter.padding is not 0 by default
		addExample("tex coords", [new BasicFilter('
			color.rg = vTextureCoord.xy;
			color.ba = vec2(1.0);
		')]);
		
		//filter with uniforms
		//initial values does not matter here, since we animating them on update()
		filterWithUniforms = new FilterWithUniforms(0.0, 0.0, 0.0);
		addExample("multiply", [filterWithUniforms]);
		
		
		// advanced stuff
		// notice how bottom right corner is WHITE this time
		// that means that vFilterCoord maps (0,0) to the top left corner and (1,1) to the bottom right corner of the sprite
		// also AdvancedFilter sets padding = 0 so the filtered area is the same size as sprite
		addExample("filter coord", [new AdvancedFilter('
			color.rg = vFilterCoord.xy;
			color.ba = vec2(1.0);
		')]);
		
		
		// masks sprite with gradient ellipse to display usage of vFilterCoord
		addExample("ellipse mask", [new AdvancedFilter('
			// top left (-1,-1), bottom right (1,1)
			vec2 relative = 2.0 * (vFilterCoord.xy - vec2(0.5));	
			
			// distance from the center of the sprite to processed pixel
			float distance = length(relative);
			
			// clamp - http://www.shaderific.com/glsl-functions/#clamp			
			color.a = clamp(0.0, 1.0, 1.0 - distance);				
		')]);
		
		
		// demonstrates displacement mapping
		addExample("displacement", [new AdvancedFilter('
			vec2 relative = vFilterCoord.xy - vec2(0.5);	
			
			// calculate displacement
			float distance = length(relative);
			relative *= (1.0 - distance);
			
			// map back to filter coord
			relative = relative + vec2(0.5);
			
			// map to texture coord
			vec2 texCoord = filterToTexCoord(relative);
			
			// get pixel value
			color = texture2D(uSampler, texCoord);
		')]);
	}
	
	function update(_:Float)
	{
		var time = Browser.window.performance.now() * 0.001;	//seconds
		filterWithUniforms.setMultiplyRGB(
			(Math.sin(time) + 1.0) * .5,	//value floats in 0.0 - 1.0
			(Math.cos(time) + 1.0) * .5,	//value floats in 0.0 - 1.0
			1.0
		);
	}

	
	/**
	 * Adds a default graphic with filters onto grid
	 * Adds click listener to toggle filters on/off
	 * @param	desc
	 * @param	filters
	 */
	function addExample(desc:String, filters:Array<Filter>)
	{
		if (exampleLeft + GRID_WIDTH > renderer.width) {
			exampleLeft = GAP;
			exampleTop += GRID_HEIGHT + GAP;
		}
		
		//add description
		var text = new Text(desc + " (on)", { fontSize: "15px" } );
		text.x = exampleLeft;
		text.y = exampleTop;
		stage.addChild(text);
		
		//add graphic
		var g = stage.addChild(Sprite.from("img/logo.png"));		
		g.x = text.x;
		g.y = text.y + text.height + 5;
		g.interactive = true;				
		g.filters = filters;		
		
		//toggler 
		var filtersEnabled = true;		
		function toggle(_:InteractionEvent) {
			filtersEnabled = !filtersEnabled;
			text.text = desc + (filtersEnabled ? " (on)" : " (off)");
			g.filters = filtersEnabled ? filters : null;	
		};
		
		g.on("mousedown", toggle);
		g.on("touchstart", toggle);
		
		exampleLeft += GAP + GRID_WIDTH;
		
		return g;

	}
	

}


/**
 * Basic filter
 * Modifies every pixel color value in some way
 * Bare minimum to get yourself started
 */
class BasicFilter extends Filter
{
	// GLSL shader code gets compiled at runtime so we can modify it before compiling it (done internaly in pixi.js)
	public function new(glsl:String)
	{		
		//inject provided glsl into default fragment shader source
		var fragSrc = FRAG_SRC_TEMPLATE.replace("%INJECT%", glsl);
		super(			
			null,		//use default vertex shader
			fragSrc,	//inject our glsl into generic fragment shader
			null		//provide only default uniforms
		);
	}
	
	//default fragment shader source for this filter
	inline static var FRAG_SRC_TEMPLATE = '
		varying vec2 vTextureCoord;		// texture coordinate provided by PIXI default vertex shader			
		uniform sampler2D uSampler;		// texture itself provided by PIXI default uniforms

		void main()
		{
			// get pixel value from uSample at vTextureCoord position
			// color is 4-component vector with rgba values
			vec4 color = texture2D(uSampler, vTextureCoord);
			// custom glsl code will be injected here
			// it will modify color value in some way
			%INJECT%
			// gl_FragColor is colors "final destination"
			gl_FragColor = color;
		}
	';
}



/**
 * Basic color filter with uniforms
 * Multiplies pixel color value with r/g/b values provided
 */
class FilterWithUniforms extends Filter
{
	public function new(r:Float, g:Float, b:Float)
	{		
		super(			
			null,		
			FRAG_SRC,
			null
		);		
		
		// this time we will provide additional uniforms
		// it's more efficient to supply one vec3 uniform instead of 3 floats
		uniforms.multiply = Float32Array.fromArray([r, g, b]);
				
	}
	
	//update uniforms value
	public function setMultiplyRGB(r:Float, g:Float, b:Float)
	{
		//uniforms is Dynamic, typechecks incoming
		(uniforms.multiply:Float32Array).set(0, r);
		(uniforms.multiply:Float32Array).set(1, g);
		(uniforms.multiply:Float32Array).set(2, b);
	}

	inline static var FRAG_SRC = '
		varying vec2 vTextureCoord;				
		uniform sampler2D uSampler;		
		uniform vec3 multiply;	//this is our Float32Array (mapped by name and type)
		
		void main()
		{
			vec4 color = texture2D(uSampler, vTextureCoord);
			color.rgb *= multiply;
			gl_FragColor = color;
		}
	';
}

/**
 * Advanced filter introduces two important aspects
 * 1. mapping from textures coords to filter coords 
 * 2. mapping from filter coords to texture coord
 */
class AdvancedFilter extends Filter
{

	public function new(glsl:String)
	{		
		super(			
			VERT_SRC,		
			FRAG_SRC.replace("%INJECT%", glsl),	
			null
		);
				
		//in order to map texture coords to filter coords we need to know display objects size
		uniforms.frameSize = Float32Array.fromArray([0, 0]);
		
		//prevent PIXI from fitting filterArea into visible screen space
		//only needed if your filtered object is partly visible
		autoFit = false;
		
		//no padding for filterArea
		padding = 0;
		
	}
	
	override public function apply(filterManager:FilterManager, input:RenderTarget, output:RenderTarget, ?clear:Bool, ?currentState:CurrentState):Void 
	{
		//update frame size
		(uniforms.frameSize:Float32Array)[0] = input.sourceFrame.width;
		(uniforms.frameSize:Float32Array)[1] = input.sourceFrame.height;
		
		//call apply :)	
		super.apply(filterManager, input, output, clear, currentState);
	}
	
	// copy of default pixis shader
	// with addition of vFilterCoord calculation
	inline static var VERT_SRC = '
		precision highp float;		//default precision is different for fragment and vertex shader, so we set one for both of them
		
		attribute vec2 aVertexPosition;
		attribute vec2 aTextureCoord;
		uniform mat3 projectionMatrix;
		
		uniform vec2 frameSize;			//filter frame size
		uniform vec4 filterArea;		//supplied by PIXI
		
		varying vec2 vTextureCoord;
		varying vec2 vFilterCoord;
		void main(void){
		   gl_Position = vec4((projectionMatrix * vec3(aVertexPosition, 1.0)).xy, 0.0, 1.0);
		   
		   //calculates filter coords
		   vFilterCoord = aTextureCoord * filterArea.xy / frameSize.xy;	//filterArea.xy - width/height in pixels
		   
		   vTextureCoord = aTextureCoord;
		}
	';
	
	inline static var FRAG_SRC = '
		precision highp float;	//default precision is different for fragment and vertex shader, so we set one for both of them
		
		varying vec2 vTextureCoord;				
		varying vec2 vFilterCoord;	//vertex shader already calculated this by: vFilterCoord = ( filterMatrix * vec3( vTextureCoord, 1.0)  ).xy;
		uniform sampler2D uSampler;	
		
		uniform vec2 frameSize;			//filter frame size
		uniform vec4 filterArea;		//supplied by PIXI
		
		// utility to map filterCoord back to texture coord
		vec2 filterToTexCoord(vec2 filterCoord)
		{
			return filterCoord * frameSize.xy / filterArea.xy;
		}
		
		void main()
		{
			vec4 color = texture2D(uSampler, vTextureCoord);
			%INJECT%
			gl_FragColor = color;
		}
	';
}