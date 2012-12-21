//
//  OsdViewerViewController.m
//  OpenSubdivViewer
//
//  Created by David Yu on 8/12/12.
//  Copyright (c) 2012 Pixar Animation Studios. All rights reserved.
//

#import "OsdViewerViewController.h"

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

//------------------------------------------------------------

// XXXdyu-api
#import <version.h>

// XXXdyu-api
namespace OpenSubdiv {
namespace OPENSUBDIV_VERSION {

class Mutex {
public:
    void Lock() {}
    void Unlock() {}
};

}
using namespace OPENSUBDIV_VERSION;
}

// XXXdyu-api
#define HBR_ADAPTIVE
#import <hbr/mesh.h>
#import <hbr/catmark.h>
#import <hbr/face.h>
#import <osd/vertex.h>

// XXXdyu-api
typedef OpenSubdiv::HbrMesh<OpenSubdiv::OsdVertex>     OsdHbrMesh;
typedef OpenSubdiv::HbrVertex<OpenSubdiv::OsdVertex>   OsdHbrVertex;
typedef OpenSubdiv::HbrFace<OpenSubdiv::OsdVertex>     OsdHbrFace;
typedef OpenSubdiv::HbrHalfedge<OpenSubdiv::OsdVertex> OsdHbrHalfedge;

#import <osd/cpuGLVertexBuffer.h>
#import <osd/cpuComputeController.h>
#import <osd/glDrawContext.h>
#import <osd/glMesh.h>

#import <iostream>

int numVertices = 0;
GLfloat *vertexData;

int numIndices = 0;
GLushort *indexData;

int numFaces = 0;
GLushort *faceData;

static void buildCube() {
    GLfloat pointsData[] = {
        1.0f, 1.0f, 1.0f,
       -1.0f, 1.0f, 1.0f,
       -1.0f,-1.0f, 1.0f,
        1.0f,-1.0f, 1.0f,

       -1.0f,-1.0f,-1.0f,
       -1.0f, 1.0f,-1.0f,
        1.0f, 1.0f,-1.0f,
        1.0f,-1.0f,-1.0f,
    };
    numVertices = (sizeof(pointsData) / sizeof(pointsData[0])) / 3;
    vertexData = (GLfloat*)calloc(numVertices * 3, sizeof(GLfloat));
    memcpy(vertexData, pointsData, sizeof(pointsData));

    GLushort nvertsData[] = {
        4, 4, 4, 4, 4, 4,
    };
    numFaces = sizeof(nvertsData) / sizeof(nvertsData[0]);
    faceData = (GLushort*)calloc(numFaces, sizeof(GLushort));
    memcpy(faceData, nvertsData, sizeof(nvertsData));

    GLushort vertsData[] = {
        0, 1, 2, 3,
        4, 5, 6, 7,

        0, 3, 7, 6,
        4, 2, 1, 5,

        0, 6, 5, 1,
        4, 7, 3, 2,
    };
    numIndices = sizeof(vertsData) / sizeof(vertsData[0]);
    indexData = (GLushort*)calloc(numIndices, sizeof(GLushort));
    memcpy(indexData, vertsData, sizeof(vertsData));
}

static void buildTorus() {
    int numSlices = 4;
    int numStacks = 8;
    float majorRadius = 1.0f;
    float minorRadius = 0.5f;

    numVertices = numSlices * numStacks;
    vertexData = (GLfloat*)calloc(3 * numVertices, sizeof(GLfloat));

    numFaces = numSlices * numStacks;
    faceData = (GLushort*)calloc(numFaces, sizeof(GLushort));

    numIndices = 4 * numSlices * numStacks;
    indexData = (GLushort*)calloc(numIndices, sizeof(GLushort));;

    for (int i=0; i<numStacks; ++i) {
        double a0 = i * 2.0 * M_PI / numStacks
                    + M_PI / numStacks;
        double x = cos(a0);
        double y = sin(a0);

        for (int j=0; j<numSlices; ++j) {
            double a1 = j * 2.0 * M_PI / numSlices
                        + M_PI / numSlices;
            double r = minorRadius * cos(a1) + majorRadius;
            double z = minorRadius * sin(a1);

            int pointOffset = i * numSlices + j;
            vertexData[pointOffset*3+0] = (float) (x * r);
            vertexData[pointOffset*3+1] = (float) (y * r);
            vertexData[pointOffset*3+2] = (float) (z);

            int faceOffset = i * numSlices + j;
            int vertBase = 4 * faceOffset;
            int pointBase = i * numSlices + j;

            int sliceOffset =
                j < numSlices-1
                        ? 1
                        : 1-numSlices;
            int stackOffset =
                i < numStacks-1
                        ? numSlices
                        : numSlices-(numStacks * numSlices);

            indexData[vertBase + 3] = pointBase;
            indexData[vertBase + 2] = pointBase + sliceOffset;
            indexData[vertBase + 1] = pointBase + sliceOffset + stackOffset;
            indexData[vertBase + 0] = pointBase               + stackOffset;
            faceData[faceOffset] = 4;
        }
    }
}

static void
_Cross(float *r, const float *a, const float *b, const float *c)
{
    float p[3] = { b[0]-a[0], b[1]-a[1], b[2]-a[2] };
    float q[3] = { c[0]-a[0], c[1]-a[1], c[2]-a[2] };
    r[0] = p[1]*q[2] - p[2]*q[1];
    r[1] = p[2]*q[0] - p[0]*q[2];
    r[2] = p[0]*q[1] - p[1]*q[0];
}

static void
_Normalize(float *r)
{
    float d = 1.0 / sqrt( r[0]*r[0] + r[1]*r[1] + r[2]*r[2] );
    r[0] *= d;
    r[1] *= d;
    r[2] *= d;
}

static void
_ComputeSmoothNormals(
        const GLushort *nverts,
        const GLushort *verts,
        int numPoints, int numFaces, int numFloatsPerPoint,
        const GLfloat *points,
        GLfloat  *normals)
{
    const GLushort * v = verts;
    for (int i=-0; i<numFaces; ++i) {
        int numVertsInFace = nverts[ i ];

        for (int j=0; j<numVertsInFace; ++j) {
            int a = v[ j ];
            int b = v[ ((j+1) < numVertsInFace ? j+1 : j+1 - numVertsInFace) ];
            int c = v[ ((j+2) < numVertsInFace ? j+2 : j+2 - numVertsInFace) ];

            float n[3];
            _Cross(n, &points[ a*numFloatsPerPoint ],
                      &points[ b*numFloatsPerPoint ],
                      &points[ c*numFloatsPerPoint ]);
            normals[b*3 + 0] -= n[0];
            normals[b*3 + 1] -= n[1];
            normals[b*3 + 2] -= n[2];
        }

        v += numVertsInFace;
    }

    for (int i=0; i<numPoints; ++i) {
        _Normalize(&(normals[i*3]));
    }
}

//------------------------------------------------------------

@interface OsdViewerViewController () {
    GLuint _meshProgram;
    GLuint _meshVertexArray;

    GLuint _hullProgram;
    GLuint _hullVertexArray;
    GLuint _hullVertexBuffer;
    GLuint _hullIndexBuffer;
    
    GLKMatrix4 _modelViewMatrix;
    GLKMatrix4 _modelViewProjectionMatrix;
    float _rotation;
    
    OpenSubdiv::OsdGLMeshInterface * _osdMesh;
}
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) GLKBaseEffect *effect;

- (void)setupGL;
- (void)tearDownGL;

- (void)setupLighting;
- (void)setupMesh;
- (void)updateMesh;

- (GLuint)loadProgram:(NSString *)shader;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;
@end

@implementation OsdViewerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;

    _osdMesh = 0;
    
    [self setupGL];
}

- (void)dealloc
{    
    delete _osdMesh;

    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        delete _osdMesh;

        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
    _meshProgram = [self loadProgram:@"MeshShader"];
    _hullProgram = [self loadProgram:@"HullShader"];
    
    self.effect = [[GLKBaseEffect alloc] init];
    self.effect.light0.enabled = GL_TRUE;
    self.effect.light0.diffuseColor = GLKVector4Make(1.0f, 0.4f, 0.4f, 1.0f);
    
    glEnable(GL_DEPTH_TEST);

    [self setupLighting];

    [self setupMesh];
    [self updateMesh];
    
    //
    // -- Mesh Vertex Array Data
    //
    glGenVertexArraysOES(1, &_meshVertexArray);
    glBindVertexArrayOES(_meshVertexArray);

    glBindBuffer(GL_ARRAY_BUFFER, _osdMesh->BindVertexBuffer());
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _osdMesh->GetDrawContext()->patchTrianglesIndexBuffer);

    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition,
                          3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(GLKVertexAttribNormal);
    glVertexAttribPointer(GLKVertexAttribNormal,
                          3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(12));

    //
    // -- Hull Vertex Array Data
    //
    glGenVertexArraysOES(1, &_hullVertexArray);
    glBindVertexArrayOES(_hullVertexArray);
    
    glGenBuffers(1, &_hullVertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _hullVertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, numVertices*3*sizeof(GLfloat), vertexData, GL_STATIC_DRAW);
    
    GLushort * hullIndexData = (GLushort*)calloc(numIndices * 2, sizeof(GLushort));
    int voffset = 0;
    for (int i=0; i<numFaces; ++i) {
        int nv = faceData[i];
        for (int j=0; j<nv; ++j) {
           hullIndexData[2*(voffset+j)] = indexData[voffset+j];
           hullIndexData[2*(voffset+j)+1] = indexData[voffset+((j+1) % nv)];
        }
        voffset += nv;
    }

    glGenBuffers(1, &_hullIndexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _hullIndexBuffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, numIndices*2*sizeof(GLushort), hullIndexData, GL_STATIC_DRAW);
    free(hullIndexData);

    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition,
                          3, GL_FLOAT, GL_FALSE, 12, BUFFER_OFFSET(0));
    
    glBindVertexArrayOES(0);
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteProgram(_meshProgram);
    glDeleteVertexArraysOES(1, &_meshVertexArray);

    glDeleteProgram(_hullProgram);
    glDeleteVertexArraysOES(1, &_hullVertexArray);
    glDeleteBuffers(1, &_hullVertexBuffer);
    glDeleteBuffers(1, &_hullIndexBuffer);
    
    self.effect = nil;
    
}

- (void)setupLighting
{
    glUseProgram(_meshProgram);

    float pos[] = { 0.0f, 0.0f, -1.0f, 0.0f };
    glUniform4fv(glGetUniformLocation(_meshProgram,
            "lightSource[0].position"), 1, pos);

    float amb[] = { 0.2f, 0.2f, 0.2f, 0.0f };
    glUniform4fv(glGetUniformLocation(_meshProgram,
            "lightSource[0].ambient"), 1, amb);

    float diff[] = { 0.8f, 0.8f, 0.8f, 0.0f };
    glUniform4fv(glGetUniformLocation(_meshProgram,
            "lightSource[0].diffuse"), 1, diff);

    float spec[] = { 0.8f, 0.8f, 0.8f, 0.0f };
    glUniform4fv(glGetUniformLocation(_meshProgram,
            "lightSource[0].specular"), 1, spec);

    float att[] = { 1.0f, 0.0f, 0.0f };
    glUniform3fv(glGetUniformLocation(_meshProgram,
            "lightSource[0].attenuation"), 1, att);

    float spotDir[] = { 0.0f, 0.0f, 1.0f };
    glUniform3fv(glGetUniformLocation(_meshProgram,
            "lightSource[0].spotDirection"), 1, spotDir);

    glUniform1f(glGetUniformLocation(_meshProgram,
            "lightSource[0].spotExponent"), 0.0f);

    glUniform1f(glGetUniformLocation(_meshProgram,
            "lightSource[0].spotCosCutoff"), -1.0f);
}

- (void)setupMesh
{
    //
    // -- ShapeData
    //
    //buildCube();
    buildTorus();

    //
    // -- HbrMesh
    //
    static OpenSubdiv::HbrCatmarkSubdivision<OpenSubdiv::OsdVertex> catmark;
    OsdHbrMesh *hmesh = new OsdHbrMesh(&catmark);

    // create new empty vertices
    OpenSubdiv::OsdVertex v;
    for (int i=0; i<numVertices; ++i) {
        hmesh->NewVertex(i, v);
    }

    // assign base mesh topology
    const GLushort *faceIndices = indexData;
    for (int i=0; i<numFaces; ++i) {
        int numVertsInFace = faceData[ i ];

        bool faceIsValid = true;
        for (int j=0; j<numVertsInFace; ++j) {
            int i0 = faceIndices[ j ];
            int i1 = faceIndices[ (j+1) % numVertsInFace ];

            OsdHbrVertex *v0 = hmesh->GetVertex(i0);
            OsdHbrVertex *v1 = hmesh->GetVertex(i1);

            // XXXdyu-api check for topology errors
        }

        if (faceIsValid) {
            std::vector<int> indices(faceIndices, faceIndices+numVertsInFace); // XXXdyu-mobile
            OsdHbrFace * face =
                hmesh->NewFace(numVertsInFace, indices.data(), 0);
        }

        faceIndices += numVertsInFace;
    }

    hmesh->Finish();

    //
    // -- OsdMesh
    //
    OpenSubdiv::OsdMeshBitset bits;
    bits.set(OpenSubdiv::MeshAdaptive, false);
    int level = 3;

    _osdMesh = new OpenSubdiv::OsdMesh<OpenSubdiv::OsdCpuGLVertexBuffer,
                                       OpenSubdiv::OsdCpuComputeController,
                                       OpenSubdiv::OsdGLDrawContext>
                                       (hmesh, 6, level, bits);

    delete hmesh;
}

- (void)updateMesh
{
    //
    // -- Mesh Data
    //
    GLfloat *normalsData = (GLfloat*)calloc(numVertices * 3, sizeof(GLfloat));
    _ComputeSmoothNormals(faceData, indexData,
                          numVertices, numFaces, 3,
                          vertexData, normalsData);

    GLfloat *interleaved = (GLfloat*)calloc(numVertices * 6, sizeof(GLfloat));
    for (int i=0; i<numVertices; ++i) {
        interleaved[i*6+0] = vertexData[i*3 + 0];
        interleaved[i*6+1] = vertexData[i*3 + 1];
        interleaved[i*6+2] = vertexData[i*3 + 2];
        interleaved[i*6+3] = normalsData[i*3 + 0];
        interleaved[i*6+4] = normalsData[i*3 + 1];
        interleaved[i*6+5] = normalsData[i*3 + 2];
    }
    free(normalsData);

    _osdMesh->UpdateVertexBuffer(interleaved, numVertices);
    free(interleaved);

    _osdMesh->Refine();
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.1f, 100.0f);
    
    self.effect.transform.projectionMatrix = projectionMatrix;
    
    GLKMatrix4 baseModelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -4.0f);
    baseModelViewMatrix = GLKMatrix4Rotate(baseModelViewMatrix, _rotation, 0.0f, 1.0f, 0.0f);
    
    // Compute the model view matrix for the object rendered with GLKit
    _modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, 0.0f);
    _modelViewMatrix = GLKMatrix4Rotate(_modelViewMatrix, _rotation, 1.0f, 1.0f, 1.0f);
    _modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, _modelViewMatrix);
    
    self.effect.transform.modelviewMatrix = _modelViewMatrix;
    
    _modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, _modelViewMatrix);
    
    _rotation += self.timeSinceLastUpdate * 0.5f;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(0.2, 0.2, 0.3, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Render the object with GLKit
    [self.effect prepareToDraw];
    
    glUseProgram(_meshProgram);

    glUniformMatrix4fv(
        glGetUniformLocation(_meshProgram, "ModelViewMatrix"),
        1, 0, _modelViewMatrix.m);
    glUniformMatrix4fv(
        glGetUniformLocation(_meshProgram, "ModelViewProjectionMatrix"),
        1, 0, _modelViewProjectionMatrix.m);
    
    float meshColor[] = { 0.2f, 0.2f, 0.8f, 1.0f };
    glVertexAttrib4f(glGetAttribLocation(_meshProgram, "color"),
        meshColor[0], meshColor[1], meshColor[2], meshColor[3]);

    glBindVertexArrayOES(_meshVertexArray);

    OpenSubdiv::OsdPatchArray const & patch =
        _osdMesh->GetDrawContext()->patchArrays[0];

    glDrawElements(GL_TRIANGLES,
                   (patch.numIndices/4)*6, GL_UNSIGNED_SHORT,
                   (void *)(patch.firstIndex * sizeof(unsigned int)));

    glUseProgram(_hullProgram);

    glUniformMatrix4fv(
        glGetUniformLocation(_hullProgram, "ModelViewProjectionMatrix"),
        1, 0, _modelViewProjectionMatrix.m);

    glBindVertexArrayOES(_hullVertexArray);

    glLineWidth(2.0);

    glDrawElements(GL_LINES,
                   numIndices * 2, GL_UNSIGNED_SHORT,
                   BUFFER_OFFSET(0));
}

#pragma mark -  OpenGL ES 2 shader compilation

- (GLuint)loadProgram:(NSString *)shader
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    GLuint program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:shader ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:shader ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(program, vertShader);
    glDeleteShader(vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(program, fragShader);
    glDeleteShader(fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(program, GLKVertexAttribPosition, "position");
    glBindAttribLocation(program, GLKVertexAttribNormal, "normal");
    
    // Link program.
    if (![self linkProgram:program]) {
        NSLog(@"Failed to link program: %d", program);
        
        glDeleteProgram(program);
        
        return 0;
    }
    
    return program;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

@end
