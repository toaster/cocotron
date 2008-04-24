#import "KGContext_gdi.h"
#import "KGLayer_gdi.h"
#import "Win32Window.h"
#import "Win32DeviceContextPrinter.h"
#import "KGDeviceContext_gdi_ddb.h"
#import "Win32DeviceContextWindow.h"
#import <AppKit/KGGraphicsState.h>
#import <AppKit/KGDeviceContext_gdi.h>
#import <AppKit/KGMutablePath.h>
#import <AppKit/KGColor.h>
#import <AppKit/KGColorSpace.h>
#import <AppKit/KGShading.h>
#import <AppKit/KGFunction.h>
#import <AppKit/KGFont.h>
#import <AppKit/KGImage.h>
#import <AppKit/KGClipPhase.h>
#import <AppKit/Win32Font.h>

static inline int float2int(float coord){
   return floorf(coord);
}

static inline BOOL transformIsFlipped(CGAffineTransform matrix){
   return (matrix.d<0)?YES:NO;
}

static NSRect Win32TransformRect(CGAffineTransform matrix,NSRect rect) {
   NSPoint point1=CGPointApplyAffineTransform(rect.origin,matrix);
   NSPoint point2=CGPointApplyAffineTransform(NSMakePoint(NSMaxX(rect),NSMaxY(rect)),matrix);

   if(point2.y<point1.y){
    float temp=point2.y;
    point2.y=point1.y;
    point1.y=temp;
   }

  return NSMakeRect(point1.x,point1.y,point2.x-point1.x,point2.y-point1.y);
}

static COLORREF RGBFromColor(KGColor *color){
   int    count=[color numberOfComponents];
   float *components=[color components];
   
   if(count==2)
    return RGB(components[0]*255,components[0]*255,components[0]*255);
   if(count==4)
    return RGB(components[0]*255,components[1]*255,components[2]*255);
    
   return RGB(0,0,0);
}

static RECT NSRectToRECT(NSRect rect) {
   RECT result;

   if(rect.size.height<0)
    rect=NSZeroRect;
   if(rect.size.width<0)
    rect=NSZeroRect;

   result.top=float2int(rect.origin.y);
   result.left=float2int(rect.origin.x);
   result.bottom=float2int(rect.origin.y+rect.size.height);
   result.right=float2int(rect.origin.x+rect.size.width);

   return result;
}

@implementation KGContext_gdi

+(BOOL)isAvailable {
   return YES;
}

+(BOOL)canInitWithWindow:(CGWindow *)window {
   return YES;
}

+(BOOL)canInitBackingWithContext:(KGContext *)context {
   return YES;
}

-initWithGraphicsState:(KGGraphicsState *)state deviceContext:(KGDeviceContext_gdi *)deviceContext {
   [self initWithGraphicsState:state];
   _deviceContext=[deviceContext retain];
   _dc=[_deviceContext dc];

   _isAdvanced=(SetGraphicsMode(_dc,GM_ADVANCED)!=0)?YES:NO;
   
   if(SetMapMode(_dc,MM_ANISOTROPIC)==0)
    NSLog(@"SetMapMode failed");
   //SetICMMode(_dc,ICM_ON); MSDN says only available on 2000, not NT.

   SetBkMode(_dc,TRANSPARENT);
   SetTextAlign(_dc,TA_BASELINE);

   _gdiFont=nil;

   return self;
}

-initWithHWND:(HWND)handle {
   KGDeviceContext_gdi    *deviceContext=[[[Win32DeviceContextWindow alloc] initWithWindowHandle:handle] autorelease];
   NSSize                  size=[deviceContext pixelSize];
   CGAffineTransform       flip={1,0,0,-1,0,size.height};
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:flip] autorelease];

   return [self initWithGraphicsState:initialState deviceContext:deviceContext];
}

-initWithPrinterDC:(HDC)printer {
   KGDeviceContext_gdi    *deviceContext=[[[Win32DeviceContextPrinter alloc] initWithDC:printer] autorelease];
   NSSize                  pointSize=[deviceContext pointSize];
   NSSize                  pixelsPerInch=[deviceContext pixelsPerInch];
   CGAffineTransform       flip={1,0,0,-1,0, pointSize.height};
   CGAffineTransform       scale=CGAffineTransformConcat(CGAffineTransformMakeScale(pixelsPerInch.width/72.0,pixelsPerInch.height/72.0),flip);
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:scale] autorelease];
      
   return [self initWithGraphicsState:initialState deviceContext:deviceContext];
}

-initWithSize:(NSSize)size window:(CGWindow *)window {
   HWND                    handle=[(Win32Window *)window windowHandle];
   KGDeviceContext_gdi    *deviceContext=[[[Win32DeviceContextWindow alloc] initWithWindowHandle:handle] autorelease];
   CGAffineTransform       flip={1,0,0,-1,0,size.height};
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:flip] autorelease];

   return [self initWithGraphicsState:initialState deviceContext:deviceContext];
}

-initWithSize:(NSSize)size context:(KGContext *)otherX useDIB:(BOOL)useDIB {
   KGContext_gdi          *other=(KGContext_gdi *)otherX;
   KGDeviceContext_gdi    *deviceContext=[[[KGDeviceContext_gdi_ddb alloc] initWithSize:size deviceContext:[other deviceContext]] autorelease];
   CGAffineTransform       flip={1,0,0,-1,0,size.height};
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:flip] autorelease];

   return [self initWithGraphicsState:initialState deviceContext:deviceContext];
}

-initWithSize:(NSSize)size context:(KGContext *)otherX {
   return [self initWithSize:size context:otherX useDIB:NO];
}

-(void)dealloc {
   [_deviceContext release];
   [_gdiFont release];
   [super dealloc];
}

-(NSSize)pointSize {
   return [[self deviceContext] pointSize];
}

-(HDC)dc {
   return _dc;
}

-(HWND)windowHandle {
   return [[[self deviceContext] windowDeviceContext] windowHandle];
}

-(HFONT)fontHandle {
   return [_gdiFont fontHandle];
}

-(KGDeviceContext_gdi *)deviceContext {
   return _deviceContext;
}

-(void)deviceSelectFontWithName:(const char *)name pointSize:(float)pointSize antialias:(BOOL)antialias {
   int height=(pointSize*GetDeviceCaps(_dc,LOGPIXELSY))/72.0;

   [_gdiFont release];
   _gdiFont=[[Win32Font alloc] initWithName:name size:NSMakeSize(0,height) antialias:antialias];
   SelectObject(_dc,[_gdiFont fontHandle]);
}

-(void)establishDeviceSpacePath:(KGPath *)path {
   CGAffineTransform    xform=[self currentState]->_deviceSpaceTransform;
   unsigned             opCount=[path numberOfElements];
   const unsigned char *elements=[path elements];
   unsigned             pointCount=[path numberOfPoints];
   const NSPoint       *points=[path points];
   unsigned             i,pointIndex;
       
   BeginPath(_dc);
   
   pointIndex=0;
   for(i=0;i<opCount;i++){
    switch(elements[i]){

     case kCGPathElementMoveToPoint:{
       NSPoint point=CGPointApplyAffineTransform(points[pointIndex++],xform);
        
       MoveToEx(_dc,float2int(point.x),float2int(point.y),NULL);
      }
      break;
       
     case kCGPathElementAddLineToPoint:{
       NSPoint point=CGPointApplyAffineTransform(points[pointIndex++],xform);
        
       LineTo(_dc,float2int(point.x),float2int(point.y));
      }
      break;

     case kCGPathElementAddCurveToPoint:{
       NSPoint cp1=CGPointApplyAffineTransform(points[pointIndex++],xform);
       NSPoint cp2=CGPointApplyAffineTransform(points[pointIndex++],xform);
       NSPoint end=CGPointApplyAffineTransform(points[pointIndex++],xform);
       POINT   points[3]={
        { float2int(cp1.x), float2int(cp1.y) },
        { float2int(cp2.x), float2int(cp2.y) },
        { float2int(end.x), float2int(end.y) },
       };
        
       PolyBezierTo(_dc,points,3);
      }
      break;

// FIX, this is wrong
     case kCGPathElementAddQuadCurveToPoint:{
       NSPoint cp1=CGPointApplyAffineTransform(points[pointIndex++],xform);
       NSPoint cp2=CGPointApplyAffineTransform(points[pointIndex++],xform);
       NSPoint end=cp2;
       POINT   points[3]={
        { float2int(cp1.x), float2int(cp1.y) },
        { float2int(cp2.x), float2int(cp2.y) },
        { float2int(end.x), float2int(end.y) },
       };
        
       PolyBezierTo(_dc,points,3);
      }
      break;

     case kCGPathElementCloseSubpath:
      CloseFigure(_dc);
      break;
    }
   }
   EndPath(_dc);
}

-(void)deviceClipReset {
   HRGN _clipRegion=CreateRectRgn(0,0,GetDeviceCaps(_dc,HORZRES),GetDeviceCaps(_dc,VERTRES));
   SelectClipRgn(_dc,_clipRegion);
   DeleteObject(_clipRegion);
}

-(void)deviceClipToNonZeroPath:(KGPath *)path {
   [self establishDeviceSpacePath:path];
   SetPolyFillMode(_dc,WINDING);
   if(!SelectClipPath(_dc,RGN_AND))
    NSLog(@"SelectClipPath failed (%i), path size= %d", GetLastError(),[path numberOfElements]);
}

-(void)deviceClipToEvenOddPath:(KGPath *)path {
   [self establishDeviceSpacePath:path];
   SetPolyFillMode(_dc,ALTERNATE);
   if(!SelectClipPath(_dc,RGN_AND))
    NSLog(@"SelectClipPath failed (%i), path size= %d", GetLastError(),[path numberOfElements]);
}

-(void)deviceClipToMask:(KGImage *)mask inRect:(NSRect)rect {
   NSUnimplementedMethod();
}

-(void)drawPathInDeviceSpace:(KGPath *)path drawingMode:(int)mode state:(KGGraphicsState *)state {
   CGAffineTransform deviceTransform=state->_deviceSpaceTransform;
   float    lineWidth=state->_lineWidth;
   KGColor *fillColor=state->_fillColor;
   KGColor *strokeColor=state->_strokeColor;

   [self establishDeviceSpacePath:path];
      
   {
    HBRUSH fillBrush=CreateSolidBrush(RGBFromColor(fillColor));
    HBRUSH oldBrush=SelectObject(_dc,fillBrush);

    if(mode==kCGPathFill || mode==kCGPathFillStroke){
     SetPolyFillMode(_dc,WINDING);
     FillPath(_dc);
    }
    if(mode==kCGPathEOFill || mode==kCGPathEOFillStroke){
     SetPolyFillMode(_dc,ALTERNATE);
     FillPath(_dc);
    }
    SelectObject(_dc,oldBrush);
    DeleteObject(fillBrush);
   }
   
   if(mode==kCGPathStroke || mode==kCGPathFillStroke || mode==kCGPathEOFillStroke){
    NSSize lineSize=CGSizeApplyAffineTransform(NSMakeSize(lineWidth,lineWidth),deviceTransform);
    HPEN   pen=CreatePen(PS_SOLID,(lineSize.width+lineSize.height)/2,RGBFromColor(strokeColor));
    HPEN   oldpen=SelectObject(_dc,pen);

    StrokePath(_dc);
    SelectObject(_dc,oldpen);
    DeleteObject(pen);
   }
}


-(void)drawPath:(CGPathDrawingMode)pathMode {

   [self drawPathInDeviceSpace:_path drawingMode:pathMode state:[self currentState] ];
   
   [_path reset];
}

-(void)showGlyphs:(const CGGlyph *)glyphs count:(unsigned)count {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];
   CGAffineTransform Trm=CGAffineTransformConcat(transformToDevice,[self currentState]->_textTransform);
   NSPoint           point=CGPointApplyAffineTransform(NSMakePoint(0,0),Trm);
   
   SetTextColor(_dc,RGBFromColor([self fillColor]));
   ExtTextOutW(_dc,point.x,point.y,ETO_GLYPH_INDEX,NULL,(void *)glyphs,count,NULL);
   
   NSSize advancement=[[self currentFont] advancementForNominalGlyphs:glyphs count:count];
   
   [self currentState]->_textTransform.tx+=advancement.width;
   [self currentState]->_textTransform.ty+=advancement.height;
}


// The problem is that the GDI gradient fill is a linear/stitched filler and the
// Mac one is a sampling one. So to preserve color variation we stitch together a lot of samples

// we could use stitched linear PDF functions better, i.e. use the intervals
// we could decompose the rectangles further and just use fills if we don't have GradientFill (or ditch GradientFill altogether)
// we could test for cases where the angle is a multiple of 90 and use the _H or _V constants if we dont have transformations
// we could decompose this better to platform generalize it

static inline float axialBandIntervalFromMagnitude(KGFunction *function,float magnitude){
   if(magnitude<1)
    return 0;

   if([function isLinear])
    return 1;
   
   if(magnitude<1)
    return 1;
   if(magnitude<4)
    return magnitude;
    
   return magnitude/4; // 4== arbitrary
}

static inline void GrayAToRGBA(float *input,float *output){
   output[0]=input[0];
   output[1]=input[0];
   output[2]=input[0];
   output[3]=input[1];
}

static inline void RGBAToRGBA(float *input,float *output){
   output[0]=input[0];
   output[1]=input[1];
   output[2]=input[2];
   output[3]=input[3];
}

static inline void CMYKAToRGBA(float *input,float *output){
   float white=1-input[3];
   
   output[0]=(input[0]>white)?0:white-input[0];
   output[1]=(input[1]>white)?0:white-input[1];
   output[2]=(input[2]>white)?0:white-input[2];
   output[3]=input[4];
}

#ifndef GRADIENT_FILL_RECT_H
#define GRADIENT_FILL_RECT_H 0
#endif

-(void)drawInUserSpace:(CGAffineTransform)matrix axialShading:(KGShading *)shading {
   KGColorSpace *colorSpace=[shading colorSpace];
   KGColorSpaceType colorSpaceType=[colorSpace type];
   KGFunction   *function=[shading function];
   const float  *domain=[function domain];
   const float  *range=[function range];
   BOOL          extendStart=[shading extendStart];
   BOOL          extendEnd=[shading extendEnd];
   NSPoint       startPoint=CGPointApplyAffineTransform([shading startPoint],matrix);
   NSPoint       endPoint=CGPointApplyAffineTransform([shading endPoint],matrix);
   NSPoint       vector=NSMakePoint(endPoint.x-startPoint.x,endPoint.y-startPoint.y);
   float         magnitude=ceilf(sqrtf(vector.x*vector.x+vector.y*vector.y));
   float         angle=(magnitude==0)?0:(atanf(vector.y/vector.x)+((vector.x<0)?M_PI:0));
   float         bandInterval=axialBandIntervalFromMagnitude(function,magnitude);
   int           bandCount=bandInterval;
   int           i,rectIndex=0;
   float         rectWidth=(bandCount==0)?0:magnitude/bandInterval;
   float         domainInterval=(bandCount==0)?0:(domain[1]-domain[0])/bandInterval;
   GRADIENT_RECT rect[1+bandCount+1];
   int           vertexIndex=0;
   TRIVERTEX     vertices[(1+bandCount+1)*2];
   float         output[[colorSpace numberOfComponents]+1];
   float         rgba[4];
   void        (*outputToRGBA)(float *,float *);
   // should use something different here so we dont get huge numbers on printers, the clip bbox?
   int           hRes=GetDeviceCaps(_dc,HORZRES);
   int           vRes=GetDeviceCaps(_dc,VERTRES);
   float         maxHeight=MAX(hRes,vRes)*2;

   typedef WINGDIAPI BOOL WINAPI (*gradientType)(HDC,PTRIVERTEX,ULONG,PVOID,ULONG,ULONG);
   HANDLE        library=LoadLibrary("MSIMG32");
   gradientType  gradientFill=(gradientType)GetProcAddress(library,"GradientFill");
      
   if(!_isAdvanced)
    return;
    
   if(gradientFill==NULL){
    NSLog(@"Unable to locate GradientFill");
    return;
   }

   switch(colorSpaceType){

    case KGColorSpaceGenericGray:
     outputToRGBA=GrayAToRGBA;
     break;
     
    case KGColorSpaceGenericRGB:
     outputToRGBA=RGBAToRGBA;
     break;
     
    case KGColorSpaceGenericCMYK:
     outputToRGBA=CMYKAToRGBA;
     break;
     
    default:
     NSLog(@"axial shading can't deal with colorspace %@",colorSpace);
     return;
   }
      
   if(extendStart){
    [function evaluateInput:domain[0] output:output];
    outputToRGBA(output,rgba);
    
    rect[rectIndex].UpperLeft=vertexIndex;
    vertices[vertexIndex].x=float2int(-maxHeight);
    vertices[vertexIndex].y=float2int(-maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;
    
    rect[rectIndex].LowerRight=vertexIndex;
 // the degenerative case for magnitude==0 is to fill the whole area with the extend
    if(magnitude!=0)
     vertices[vertexIndex].x=float2int(0);
    else {
     vertices[vertexIndex].x=float2int(maxHeight);
     extendEnd=NO;
    }
    vertices[vertexIndex].y=float2int(maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;

    rectIndex++;
   }
   
   for(i=0;i<bandCount;i++){
    float x0=domain[0]+i*domainInterval;
    float x1=domain[0]+(i+1)*domainInterval;
   
    rect[rectIndex].UpperLeft=vertexIndex;
    vertices[vertexIndex].x=float2int(i*rectWidth);
    vertices[vertexIndex].y=float2int(-maxHeight);
    [function evaluateInput:x0 output:output];
    outputToRGBA(output,rgba);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;
    
    rect[rectIndex].LowerRight=vertexIndex;
    vertices[vertexIndex].x=float2int((i+1)*rectWidth);
    vertices[vertexIndex].y=float2int(maxHeight);
    [function evaluateInput:x1 output:output];
    outputToRGBA(output,rgba);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;

    rectIndex++;
   }
   
   if(extendEnd){
    [function evaluateInput:domain[1] output:output];
    outputToRGBA(output,rgba);

    rect[rectIndex].UpperLeft=vertexIndex;
    vertices[vertexIndex].x=float2int(i*rectWidth);
    vertices[vertexIndex].y=float2int(-maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;
    
    rect[rectIndex].LowerRight=vertexIndex;
    vertices[vertexIndex].x=float2int(maxHeight);
    vertices[vertexIndex].y=float2int(maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;

    rectIndex++;
   }
   
   if(rectIndex==0)
    return;
   
   {
    XFORM current;
    XFORM translate={1,0,0,1,startPoint.x,startPoint.y};
    XFORM rotate={cos(angle),sin(angle),-sin(angle),cos(angle),0,0};
     
    if(!GetWorldTransform(_dc,&current))
     NSLog(@"GetWorldTransform failed");
     
    if(!ModifyWorldTransform(_dc,&rotate,MWT_RIGHTMULTIPLY))
     NSLog(@"ModifyWorldTransform failed");
    if(!ModifyWorldTransform(_dc,&translate,MWT_RIGHTMULTIPLY))
     NSLog(@"ModifyWorldTransform failed");
    
    if(!gradientFill(_dc,vertices,vertexIndex,rect,rectIndex,GRADIENT_FILL_RECT_H))
     NSLog(@"GradientFill failed");

    if(!SetWorldTransform(_dc,&current))
     NSLog(@"GetWorldTransform failed");
   }
   
}

static int appendCircle(NSPoint *cp,int position,float x,float y,float radius,CGAffineTransform matrix){
   int i;
   
   KGMutablePathEllipseToBezier(cp+position,x,y,radius,radius);
   for(i=0;i<13;i++)
    cp[position+i]=CGPointApplyAffineTransform(cp[position+i],matrix);
    
   return position+13;
}

static void appendCircleToDC(HDC dc,NSPoint *cp){
   POINT   cPOINT[13];
   int     i,count=13;

   for(i=0;i<count;i++){
    cPOINT[i].x=float2int(cp[i].x);
    cPOINT[i].y=float2int(cp[i].y);
   }
   
   MoveToEx(dc,cPOINT[0].x,cPOINT[0].y,NULL);      
   PolyBezierTo(dc,cPOINT+1,count-1);
}

static void appendCircleToPath(HDC dc,float x,float y,float radius,CGAffineTransform matrix){
   NSPoint cp[13];
   
   appendCircle(cp,0,x,y,radius,matrix);
   appendCircleToDC(dc,cp);
}

static inline float numberOfRadialBands(KGFunction *function,NSPoint startPoint,NSPoint endPoint,float startRadius,float endRadius,CGAffineTransform matrix){
   NSPoint startRadiusPoint=NSMakePoint(startRadius,0);
   NSPoint endRadiusPoint=NSMakePoint(endRadius,0);
   
   startPoint=CGPointApplyAffineTransform(startPoint,matrix);
   endPoint=CGPointApplyAffineTransform(endPoint,matrix);
   
   startRadiusPoint=CGPointApplyAffineTransform(startRadiusPoint,matrix);
   endRadiusPoint=CGPointApplyAffineTransform(endRadiusPoint,matrix);
{
   NSPoint lineVector=NSMakePoint(endPoint.x-startPoint.x,endPoint.y-startPoint.y);
   float   lineMagnitude=ceilf(sqrtf(lineVector.x*lineVector.x+lineVector.y*lineVector.y));
   NSPoint radiusVector=NSMakePoint(endRadiusPoint.x-startRadiusPoint.x,endRadiusPoint.y-startRadiusPoint.y);
   float   radiusMagnitude=ceilf(sqrtf(radiusVector.x*radiusVector.x+radiusVector.y*radiusVector.y))*2;
   float   magnitude=MAX(lineMagnitude,radiusMagnitude);

   return magnitude;
}
}

// FIX, still lame
static BOOL controlPointsOutsideClip(HDC dc,NSPoint cp[13]){
   NSRect clipRect,cpRect;
   RECT   gdiRect;
   int    i;
   
   if(!GetClipBox(dc,&gdiRect)){
    NSLog(@"GetClipBox failed");
    return NO;
   }
   clipRect.origin.x=gdiRect.left;
   clipRect.origin.y=gdiRect.top;
   clipRect.size.width=gdiRect.right-gdiRect.left;
   clipRect.size.height=gdiRect.bottom-gdiRect.top;
   
   clipRect.origin.x-=clipRect.size.width;
   clipRect.origin.y-=clipRect.size.height;
   clipRect.size.width*=3;
   clipRect.size.height*=3;
   
   for(i=0;i<13;i++)
    if(cp[i].x>50000 || cp[i].x<-50000 || cp[i].y>50000 || cp[i].y<-50000)
     return YES;
     
   for(i=0;i<13;i++)
    if(NSPointInRect(cp[i],clipRect))
     return NO;
     
   return YES;
}


static void extend(HDC dc,int i,int direction,float bandInterval,NSPoint startPoint,NSPoint endPoint,float startRadius,float endRadius,CGAffineTransform matrix){
// - some edge cases of extend are either slow or don't fill bands accurately but these are undesirable gradients

    {
     NSPoint lineVector=NSMakePoint(endPoint.x-startPoint.x,endPoint.y-startPoint.y);
     float   lineMagnitude=ceilf(sqrtf(lineVector.x*lineVector.x+lineVector.y*lineVector.y));
     
     if((lineMagnitude+startRadius)<endRadius){
      BeginPath(dc);
      if(direction<0)
       appendCircleToPath(dc,startPoint.x,startPoint.y,startRadius,matrix);
      else {
       NSPoint point=CGPointApplyAffineTransform(endPoint,matrix);

       appendCircleToPath(dc,endPoint.x,endPoint.y,endRadius,matrix);
       // FIX, lame
       appendCircleToPath(dc,point.x,point.y,1000000,CGAffineTransformIdentity);
      }
      EndPath(dc);
      FillPath(dc);
      return;
     }
     
     if((lineMagnitude+endRadius)<startRadius){
      BeginPath(dc);
      if(direction<0){
       NSPoint point=CGPointApplyAffineTransform(startPoint,matrix);
       
       appendCircleToPath(dc,startPoint.x,startPoint.y,startRadius,matrix);
       // FIX, lame
       appendCircleToPath(dc,point.x,point.y,1000000,CGAffineTransformIdentity);
      }
      else {
       appendCircleToPath(dc,endPoint.x,endPoint.y,endRadius,matrix);
      }
      EndPath(dc);
      FillPath(dc);
      return;
     }
    }

    for(;;i+=direction){
     float position,x,y,radius;
     RECT  check;
     NSPoint cp[13];
   
     BeginPath(dc);

     position=(float)i/bandInterval;
     x=startPoint.x+position*(endPoint.x-startPoint.x);
     y=startPoint.y+position*(endPoint.y-startPoint.y);
     radius=startRadius+position*(endRadius-startRadius);
     appendCircle(cp,0,x,y,radius,matrix);
     appendCircleToDC(dc,cp);
    
     position=(float)(i+direction)/bandInterval;
     x=startPoint.x+position*(endPoint.x-startPoint.x);
     y=startPoint.y+position*(endPoint.y-startPoint.y);
     radius=startRadius+position*(endRadius-startRadius);
     appendCircle(cp,0,x,y,radius,matrix);
     appendCircleToDC(dc,cp);
     
     EndPath(dc);

     FillPath(dc);
     
     if(radius<=0)
      break;
 
     if(controlPointsOutsideClip(dc,cp))
      break;
    }
}

-(void)drawInUserSpace:(CGAffineTransform)matrix radialShading:(KGShading *)shading {
/* - band interval needs to be improved
    - does not factor resolution/scaling can cause banding
    - does not factor color sampling rate, generates multiple bands for same color
 */
   KGColorSpace *colorSpace=[shading colorSpace];
   KGColorSpaceType colorSpaceType=[colorSpace type];
   KGFunction   *function=[shading function];
   const float  *domain=[function domain];
   const float  *range=[function range];
   BOOL          extendStart=[shading extendStart];
   BOOL          extendEnd=[shading extendEnd];
   float         startRadius=[shading startRadius];
   float         endRadius=[shading endRadius];
   NSPoint       startPoint=[shading startPoint];
   NSPoint       endPoint=[shading endPoint];
   float         bandInterval=numberOfRadialBands(function,startPoint,endPoint,startRadius,endRadius,matrix);
   int           i,bandCount=bandInterval;
   float         domainInterval=(bandCount==0)?0:(domain[1]-domain[0])/bandInterval;
   float         output[[colorSpace numberOfComponents]+1];
   float         rgba[4];
   void        (*outputToRGBA)(float *,float *);

   switch(colorSpaceType){

    case KGColorSpaceGenericGray:
     outputToRGBA=GrayAToRGBA;
     break;
     
    case KGColorSpaceGenericRGB:
     outputToRGBA=RGBAToRGBA;
     break;
     
    case KGColorSpaceGenericCMYK:
     outputToRGBA=CMYKAToRGBA;
     break;
     
    default:
     NSLog(@"radial shading can't deal with colorspace %@",colorSpace);
     return;
   }

   if(extendStart){
    HBRUSH brush;

    [function evaluateInput:domain[0] output:output];
    outputToRGBA(output,rgba);
    brush=CreateSolidBrush(RGB(rgba[0]*255,rgba[1]*255,rgba[2]*255));
    SelectObject(_dc,brush);
    SetPolyFillMode(_dc,ALTERNATE);
    extend(_dc,0,-1,bandInterval,startPoint,endPoint,startRadius,endRadius,matrix);
    DeleteObject(brush);
   }
   
   for(i=0;i<bandCount;i++){
    HBRUSH brush;
    float position,x,y,radius;
    float x0=((domain[0]+i*domainInterval)+(domain[0]+(i+1)*domainInterval))/2; // midpoint color between edges
    
    BeginPath(_dc);

    position=(float)i/bandInterval;
    x=startPoint.x+position*(endPoint.x-startPoint.x);
    y=startPoint.y+position*(endPoint.y-startPoint.y);
    radius=startRadius+position*(endRadius-startRadius);
    appendCircleToPath(_dc,x,y,radius,matrix);
    
    if(i+1==bandCount)
     appendCircleToPath(_dc,endPoint.x,endPoint.y,endRadius,matrix);
    else {
     position=(float)(i+1)/bandInterval;
     x=startPoint.x+position*(endPoint.x-startPoint.x);
     y=startPoint.y+position*(endPoint.y-startPoint.y);
     radius=startRadius+position*(endRadius-startRadius);
     appendCircleToPath(_dc,x,y,radius,matrix);
    }

    EndPath(_dc);

    [function evaluateInput:x0 output:output];
    outputToRGBA(output,rgba);
    brush=CreateSolidBrush(RGB(output[0]*255,output[1]*255,output[2]*255));
    SelectObject(_dc,brush);
    SetPolyFillMode(_dc,ALTERNATE);
    FillPath(_dc);
    DeleteObject(brush);
   }
   
   if(extendEnd){
    HBRUSH brush;
    
    [function evaluateInput:domain[1] output:output];
    outputToRGBA(output,rgba);
    brush=CreateSolidBrush(RGB(rgba[0]*255,rgba[1]*255,rgba[2]*255));
    SelectObject(_dc,brush);
    SetPolyFillMode(_dc,ALTERNATE);
    extend(_dc,i,1,bandInterval,startPoint,endPoint,startRadius,endRadius,matrix);

    DeleteObject(brush);
   }
}

-(void)drawShading:(KGShading *)shading {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];

  if([shading isAxial])
   [self drawInUserSpace:transformToDevice axialShading:shading];
  else
   [self drawInUserSpace:transformToDevice radialShading:shading];
}

#if 1
void CGGraphicsSourceOver_rgba32_onto_bgrx32(unsigned char *sourceRGBA,unsigned char *resultBGRX,int width,int height,float fraction) {
   int sourceIndex=0;
   int sourceLength=width*height*4;
   int destinationReadIndex=0;
   int destinationWriteIndex=0;

   fraction *= 256.0/255.0;
   while(sourceIndex<sourceLength){
    unsigned srcr=sourceRGBA[sourceIndex++];
    unsigned srcg=sourceRGBA[sourceIndex++];
    unsigned srcb=sourceRGBA[sourceIndex++];
    unsigned srca=sourceRGBA[sourceIndex++]*fraction;

    unsigned dstb=resultBGRX[destinationReadIndex++];
    unsigned dstg=resultBGRX[destinationReadIndex++];
    unsigned dstr=resultBGRX[destinationReadIndex++];
    unsigned dsta=256-srca;

    destinationReadIndex++;

    dstr=(srcr*srca+dstr*dsta)>>8;
    dstg=(srcg*srca+dstg*dsta)>>8;
    dstb=(srcb*srca+dstb*dsta)>>8;

    resultBGRX[destinationWriteIndex++]=dstb;
    resultBGRX[destinationWriteIndex++]=dstg;
    resultBGRX[destinationWriteIndex++]=dstr;
    destinationWriteIndex++; // skip x
   }
}

-(void)drawBitmapImage:(KGImage *)image inRect:(NSRect)rect ctm:(CGAffineTransform)ctm fraction:(float)fraction  {
   int            width=[image width];
   int            height=[image height];
   const unsigned int *data=[image bytes];
   HDC            sourceDC=_dc;
   HDC            combineDC;
   int            combineWidth=width;
   int            combineHeight=height;
   NSPoint        point=CGPointApplyAffineTransform(rect.origin,ctm);
   HBITMAP        bitmap;
   BITMAPINFO     info;
   void          *bits;
   unsigned char *combineBGRX;
   unsigned char *imageRGBA=(void *)data;

   if(transformIsFlipped(ctm))
    point.y-=rect.size.height;

   if((combineDC=CreateCompatibleDC(sourceDC))==NULL){
    NSLog(@"CreateCompatibleDC failed");
    return;
   }

   info.bmiHeader.biSize=sizeof(BITMAPINFO);
   info.bmiHeader.biWidth=combineWidth;
   info.bmiHeader.biHeight=-combineHeight;
   info.bmiHeader.biPlanes=1;
   info.bmiHeader.biBitCount=32;
   info.bmiHeader.biCompression=BI_RGB;
   info.bmiHeader.biSizeImage=0;
   info.bmiHeader.biXPelsPerMeter=0;
   info.bmiHeader.biYPelsPerMeter=0;
   info.bmiHeader.biClrUsed=0;
   info.bmiHeader.biClrImportant=0;

   if((bitmap=CreateDIBSection(sourceDC,&info,DIB_RGB_COLORS,&bits,NULL,0))==NULL){
    NSLog(@"CreateDIBSection failed");
    return;
   }
   combineBGRX=bits;
   SelectObject(combineDC,bitmap);

   BitBlt(combineDC,0,0,combineWidth,combineHeight,sourceDC,point.x,point.y,SRCCOPY);
   GdiFlush();

   CGGraphicsSourceOver_rgba32_onto_bgrx32(imageRGBA,combineBGRX,width,height,fraction);

   BitBlt(sourceDC,point.x,point.y,combineWidth,combineHeight,combineDC,0,0,SRCCOPY);
   DeleteObject(bitmap);
   DeleteDC(combineDC);
}

#else
// a work in progress
static void zeroBytes(void *bytes,int size){
   int i;
   
   for(i=0;i<size;i++)
    ((char *)bytes)[i]=0;
}

-(void)drawBitmapImage:(KGImage *)image inRect:(NSRect)rect ctm:(CGAffineTransform)ctm fraction:(float)fraction  {
   int            width=[image width];
   int            height=[image height];
   const unsigned char *bytes=[image bytes];
   HDC            sourceDC;
   BITMAPV4HEADER header;
   HBITMAP        bitmap;
   HGDIOBJ        oldBitmap;
   BLENDFUNCTION  blendFunction;
   
   if((sourceDC=CreateCompatibleDC(_dc))==NULL){
    NSLog(@"CreateCompatibleDC failed");
    return;
   }
   
   zeroBytes(&header,sizeof(header));
 
   header.bV4Size=sizeof(BITMAPINFOHEADER);
   header.bV4Width=width;
   header.bV4Height=height;
   header.bV4Planes=1;
   header.bV4BitCount=32;
   header.bV4V4Compression=BI_RGB;
   header.bV4SizeImage=width*height*4;
   header.bV4XPelsPerMeter=0;
   header.bV4YPelsPerMeter=0;
   header.bV4ClrUsed=0;
   header.bV4ClrImportant=0;
#if 0
   header.bV4RedMask=0xFF000000;
   header.bV4GreenMask=0x00FF0000;
   header.bV4BlueMask=0x0000FF00;
   header.bV4AlphaMask=0x000000FF;
#else
//   header.bV4RedMask=  0x000000FF;
//   header.bV4GreenMask=0x0000FF00;
//   header.bV4BlueMask= 0x00FF0000;
//   header.bV4AlphaMask=0xFF000000;
#endif
   header.bV4CSType=0;
  // header.bV4Endpoints;
  // header.bV4GammaRed;
  // header.bV4GammaGreen;
  // header.bV4GammaBlue;
   
   {
    char *bits;
    int  i;
    
   if((bitmap=CreateDIBSection(sourceDC,&header,DIB_RGB_COLORS,&bits,NULL,0))==NULL){
    NSLog(@"CreateDIBSection failed");
    return;
   }
   for(i=0;i<width*height*4;i++){
    bits[i]=0x00;
   }
   }
   if((oldBitmap=SelectObject(sourceDC,bitmap))==NULL)
    NSLog(@"SelectObject failed");

   rect=Win32TransformRect(ctm,rect);

   blendFunction.BlendOp=AC_SRC_OVER;
   blendFunction.BlendFlags=0;
   blendFunction.SourceConstantAlpha=0xFF;
   blendFunction.BlendOp=AC_SRC_ALPHA;
   {
    typedef WINGDIAPI BOOL WINAPI (*alphaType)(HDC,int,int,int,int,HDC,int,int,int,int,BLENDFUNCTION);

    HANDLE library=LoadLibrary("MSIMG32");
    alphaType alphaBlend=(alphaType)GetProcAddress(library,"AlphaBlend");

    if(alphaBlend==NULL)
     NSLog(@"Unable to get AlphaBlend",alphaBlend);
    else {
     if(!alphaBlend(_dc,rect.origin.x,rect.origin.y,rect.size.width,rect.size.height,sourceDC,0,0,width,height,blendFunction))
      NSLog(@"AlphaBlend failed");
    }
   }

   DeleteObject(bitmap);s
   SelectObject(sourceDC,oldBitmap);
   DeleteDC(sourceDC);
}
#endif

-(void)drawImage:(KGImage *)image inRect:(NSRect)rect {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];

   if([image bitsPerComponent]!=8){
    NSLog(@"Does not support bitsPerComponent=%d",[image bitsPerComponent]);
    return;
   }
   if([image bitsPerPixel]!=32){
    NSLog(@"Does not support bitsPerPixel=%d",[image bitsPerPixel]);
    return;
   }
   
   [self drawBitmapImage:image inRect:rect ctm:transformToDevice fraction:[[self fillColor] alpha]];
}

-(void)copyColorsToContext:(KGContext_gdi *)other size:(NSSize)size toPoint:(NSPoint)toPoint  {
   BitBlt([other dc],toPoint.x,toPoint.y,size.width,size.height,_dc,0,0,SRCCOPY);
}

-(void)copyColorsToContext:(KGContext_gdi *)other size:(NSSize)size {
   [self copyColorsToContext:other size:size toPoint:NSMakePoint(0,0)];
}

-(void)drawOther:(KGContext_gdi *)other inRect:(NSRect)rect ctm:(CGAffineTransform)ctm {
   rect.origin=CGPointApplyAffineTransform(rect.origin,ctm);

   if(transformIsFlipped(ctm))
    rect.origin.y-=rect.size.height;

   [other copyColorsToContext:self size:rect.size toPoint:rect.origin];
}

-(void)drawLayer:(KGLayer *)layer inRect:(NSRect)rect {
   KGContext *context=[layer context];
   
   if(![context isKindOfClass:[KGContext_gdi class]]){
    NSLog(@"layer class is not right %@!=%@",[context class],[self class]);
    return;
   }
   
   [self drawOther:(KGContext_gdi *)context inRect:rect ctm:[self currentState]->_deviceSpaceTransform];
}

-(void)copyBitsInRect:(NSRect)rect toPoint:(NSPoint)point gState:(int)gState {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];
   NSRect  srcRect=Win32TransformRect(transformToDevice,rect);
   NSRect  dstRect=Win32TransformRect(transformToDevice,NSMakeRect(point.x,point.y,rect.size.width,rect.size.height));
   NSRect  scrollRect=NSUnionRect(srcRect,dstRect);
   int     dx=dstRect.origin.x-srcRect.origin.x;
   int     dy=dstRect.origin.y-srcRect.origin.y;
   RECT    winScrollRect=NSRectToRECT(scrollRect);

   ScrollDC(_dc,dx,dy,&winScrollRect,&winScrollRect,NULL,NULL);
}

-(KGLayer *)layerWithSize:(NSSize)size unused:(NSDictionary *)unused {
   return [[[KGLayer_gdi alloc] initRelativeToContext:self size:size unused:unused] autorelease];
}

-(void)beginPrintingWithDocumentName:(NSString *)documentName {
   [[self deviceContext] beginPrintingWithDocumentName:documentName];
}

-(void)endPrinting {
   [[self deviceContext] endPrinting];
}

-(void)beginPage:(const NSRect *)mediaBox {
   [[self deviceContext] beginPage];
}

-(void)endPage {
   [[self deviceContext] endPage];
}

-(BOOL)getImageableRect:(NSRect *)rect {
   KGDeviceContext_gdi *deviceContext=[self deviceContext];
   if(deviceContext==nil)
    return NO;
    
   *rect=[deviceContext imageableRect];
   return YES;
}

-(void)drawContext:(KGContext *)other inRect:(CGRect)rect {
   if(![other isKindOfClass:[KGContext_gdi class]])
    return;
   
   CGAffineTransform ctm=[self userSpaceToDeviceSpaceTransform];
         
   [self drawOther:(KGContext_gdi *)other inRect:rect ctm:ctm];
 }

-(void)copyContext:(KGContext *)other size:(NSSize)size {
   if(![other isKindOfClass:[KGContext_gdi class]])
    return;

   [self drawOther:(KGContext_gdi *)other inRect:NSMakeRect(0,0,size.width,size.height) ctm:CGAffineTransformIdentity];
}

-(void)flush {
   GdiFlush();
}

-(NSData *)captureBitmapInRect:(NSRect)rect {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];
   NSPoint           pt = CGPointApplyAffineTransform(rect.origin, transformToDevice);
   int               width = rect.size.width;
   int               height = rect.size.height;
   unsigned long     bmSize = 4*width*height;
   void             *bmBits;
   HBITMAP           bmHandle;
   BITMAPFILEHEADER  bmFileHeader = {0, 0, 0, 0, 0};
   BITMAPINFO        bmInfo;

   if (transformIsFlipped(transformToDevice))
      pt.y -= rect.size.height;

   HDC destDC = CreateCompatibleDC(_dc);
   if (destDC == NULL)
   {
      NSLog(@"CreateCompatibleDC failed");
      return nil;
   }

   bmInfo.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
   bmInfo.bmiHeader.biWidth=width;
   bmInfo.bmiHeader.biHeight=height;
   bmInfo.bmiHeader.biPlanes=1;
   bmInfo.bmiHeader.biBitCount=32;
   bmInfo.bmiHeader.biCompression=BI_RGB;
   bmInfo.bmiHeader.biSizeImage=0;
   bmInfo.bmiHeader.biXPelsPerMeter=0;
   bmInfo.bmiHeader.biYPelsPerMeter=0;
   bmInfo.bmiHeader.biClrUsed=0;
   bmInfo.bmiHeader.biClrImportant=0;

   bmHandle = CreateDIBSection(_dc, &bmInfo, DIB_RGB_COLORS, &bmBits, NULL, 0);
   if (bmHandle == NULL)
   {
      NSLog(@"CreateDIBSection failed");
      return nil;
   }

   SelectObject(destDC, bmHandle);
   BitBlt(destDC, 0, 0, width, height, _dc, pt.x, pt.y, SRCCOPY);
   GdiFlush();

   ((char *)&bmFileHeader)[0] = 'B';
   ((char *)&bmFileHeader)[1] = 'M';
   bmFileHeader.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
   bmFileHeader.bfSize = bmFileHeader.bfOffBits + bmSize;

   NSMutableData *result = [NSMutableData dataWithBytes:&bmFileHeader length:sizeof(BITMAPFILEHEADER)];
   [result appendBytes:&bmInfo.bmiHeader length:sizeof(BITMAPINFOHEADER)];
   [result appendBytes:bmBits length:bmSize];
   
   DeleteObject(bmHandle);
   DeleteDC(destDC);

   return result;
}

@end
