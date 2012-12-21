#include <jni.h>
#include <android/log.h>

// XXXdyu-api
#include <version.h>

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
#include <hbr/mesh.h>
#include <hbr/catmark.h>
#include <hbr/face.h>
#include <osd/vertex.h>

// XXXdyu-api
typedef OpenSubdiv::HbrMesh<OpenSubdiv::OsdVertex>     OsdHbrMesh;
typedef OpenSubdiv::HbrVertex<OpenSubdiv::OsdVertex>   OsdHbrVertex;
typedef OpenSubdiv::HbrFace<OpenSubdiv::OsdVertex>     OsdHbrFace;
typedef OpenSubdiv::HbrHalfedge<OpenSubdiv::OsdVertex> OsdHbrHalfedge;

#include <osd/cpuGLVertexBuffer.h>
#include <osd/cpuComputeController.h>
#include <osd/glDrawContext.h>
#include <osd/glMesh.h>

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <tr1/memory>
#include <vector>

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define  LOG_TAG    "AndroidOsd"
#define  LOGI(...)  __android_log_print(ANDROID_LOG_INFO,LOG_TAG,__VA_ARGS__)
#define  LOGE(...)  __android_log_print(ANDROID_LOG_ERROR,LOG_TAG,__VA_ARGS__)

typedef std::tr1::shared_ptr<class OsdMeshWrapper> OsdMeshWrapperSharedPtr;

class OsdMeshWrapper {
public:
    OsdMeshWrapper() :
        _meshHandleId(++_meshHandleIdGen),
        _level(0),
        _numPoints(0), _numFloatsPerPoint(0),
        _osdMesh(0),
        _trianglesIndexBuffer(0), _trianglesIndexCount(0) {}
    ~OsdMeshWrapper();

    int GetMeshHandleId() const {
        return _meshHandleId;
    }

    GLuint GetVertexBufferId() const {
        return _osdMesh->BindVertexBuffer();
    }

    GLuint GetTrianglesIndexBufferId() const {
        return _trianglesIndexBuffer;
    }

    GLuint GetTrianglesIndexCount() const {
        return _trianglesIndexCount;
    }

    void CreateCatmarkMesh(
        int level, int numPoints, int numFloatsPerPoint,
        int nvertsSize, const jint *nverts,
        int vertsSize, const jint *verts);

    void UpdatePoints(int level, jfloat *points);

private:
    static int _meshHandleIdGen;
    int _meshHandleId;

    int _level;
    int _numPoints;
    int _numFloatsPerPoint;

    OpenSubdiv::OsdGLMeshInterface *_osdMesh;

    GLuint _trianglesIndexBuffer;
    int _trianglesIndexCount;

    std::vector<int> _nverts;
    std::vector<int> _verts;
};

int OsdMeshWrapper::_meshHandleIdGen = 0;

OsdMeshWrapper::~OsdMeshWrapper()
{
    delete _osdMesh;
}

void
OsdMeshWrapper::CreateCatmarkMesh(
    int level, int numPoints, int numFloatsPerPoint,
    int nvertsSize, const jint *nverts,
    int vertsSize, const jint *verts)
{
    static OpenSubdiv::HbrCatmarkSubdivision<OpenSubdiv::OsdVertex> catmark;
    OsdHbrMesh *hmesh = new OsdHbrMesh(&catmark);

    // create new empty vertices
    OpenSubdiv::OsdVertex v;
    for (int i=0; i<numPoints; ++i) {
        hmesh->NewVertex(i, v);
    }

    // assign base mesh topology
    const jint *faceIndices = verts;
    for (int i=0; i<nvertsSize; ++i) {
        int numVertsInFace = nverts[ i ];

        bool faceIsValid = true;
        for (int j=0; j<numVertsInFace; ++j) {
            int i0 = faceIndices[ j ];
            int i1 = faceIndices[ (j+1) % numVertsInFace ];

            OsdHbrVertex *v0 = hmesh->GetVertex(i0);
            OsdHbrVertex *v1 = hmesh->GetVertex(i1);

            // XXXdyu-api check for topology errors
        }

        if (faceIsValid) {
            OsdHbrFace * face =
                hmesh->NewFace(numVertsInFace, const_cast<int *>(faceIndices), 0);
        }

        faceIndices += numVertsInFace;
    }

    hmesh->Finish();

    _level = level;
    _numPoints = numPoints;
    _numFloatsPerPoint = numFloatsPerPoint;

    OpenSubdiv::OsdMeshBitset bits;
    bits.set(OpenSubdiv::MeshAdaptive, false);

    _osdMesh = new OpenSubdiv::OsdMesh<OpenSubdiv::OsdCpuGLVertexBuffer,
                                       OpenSubdiv::OsdCpuComputeController,
                                       OpenSubdiv::OsdGLDrawContext>
                                       (hmesh, _numFloatsPerPoint+3, _level, bits); //XXXdyu

    delete hmesh;

    _nverts.assign(nverts, nverts+nvertsSize);
    _verts.assign(verts, verts+vertsSize);
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
        const std::vector<int> & nverts,
        const std::vector<int> & verts,
        int numPoints, int numFloatsPerPoint, const jfloat *points,
        std::vector<float> *normals)
{
    normals->resize(3 * numPoints, 0.0f);

    const int * v = verts.data();
    for (int i=-0; i<nverts.size(); ++i) {
        int numVertsInFace = nverts[ i ];

        for (int j=0; j<numVertsInFace; ++j) {
            int a = v[ j ];
            int b = v[ ((j+1) < numVertsInFace ? j+1 : j+1 - numVertsInFace) ];
            int c = v[ ((j+2) < numVertsInFace ? j+2 : j+2 - numVertsInFace) ];

            float n[3];
            _Cross(n, &points[ a*numFloatsPerPoint ],
                      &points[ b*numFloatsPerPoint ],
                      &points[ c*numFloatsPerPoint ]);
            (*normals)[b*3 + 0] -= n[0];
            (*normals)[b*3 + 1] -= n[1];
            (*normals)[b*3 + 2] -= n[2];
        }

        v += numVertsInFace;
    }

    for (int i=0; i<normals->size()/3; ++i) {
        _Normalize(&((*normals)[i*3]));
    }
}

void
OsdMeshWrapper::UpdatePoints(int level, jfloat *points)
{
    std::vector<float> normals;
    _ComputeSmoothNormals(_nverts, _verts,
                          _numPoints, _numFloatsPerPoint, points,
                          &normals);

    std::vector<float> interleaved;
    for (int i=0; i<_numPoints; ++i) {
        for (int j=0; j<_numFloatsPerPoint; ++j) {
            interleaved.push_back(points[i*_numFloatsPerPoint + j]);
        }
        interleaved.push_back(normals[i*3 + 0]);
        interleaved.push_back(normals[i*3 + 1]);
        interleaved.push_back(normals[i*3 + 2]);
    }

    _osdMesh->UpdateVertexBuffer(interleaved.data(), _numPoints);

    _osdMesh->Refine();

    _trianglesIndexBuffer = _osdMesh->GetDrawContext()->patchTrianglesIndexBuffer;
    _trianglesIndexCount = (_osdMesh->GetDrawContext()->patchArrays[0].numIndices/4)*6;
}

////////
// Mesh Wrapper Registry
////////

static OsdMeshWrapperSharedPtr registry;

static
OsdMeshWrapperSharedPtr
NewWrapper()
{
    registry.reset(new OsdMeshWrapper());
    return registry;
}

static
OsdMeshWrapperSharedPtr
GetWrapper(int meshHandleId)
{
    return registry;
}

static
void
DeleteWrapper(int meshHandleId)
{
    registry.reset();
}

////////
// JNI Wrapper methods
////////

extern "C" {
    JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_CreateCatmarkMesh(
        JNIEnv * env, jclass,
        jint level, jintArray nvertsArray, jintArray vertsArray,
        jint numFloatsPerPoint, jfloatArray pointsArray);

    JNIEXPORT void JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_DeleteMesh(
        JNIEnv * env, jobject obj, jint meshHandleId);

    JNIEXPORT void JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_UpdatePoints(
        JNIEnv * env, jclass, jint meshHandleId,
        jint level, jfloatArray pointsArray);

    JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_GetVertexBufferId(
        JNIEnv * env, jclass, jint meshHandleId);

    JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_GetTrianglesIndexBufferId(
        JNIEnv * env, jclass, jint meshHandleId);

    JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_GetTrianglesIndexCount(
        JNIEnv * env, jclass, jint meshHandleId);
};

JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_CreateCatmarkMesh(
    JNIEnv * env, jclass,
    jint level, jintArray nvertsArray, jintArray vertsArray,
    jint numFloatsPerPoint, jfloatArray pointsArray)
{
    int nvertsSize = env->GetArrayLength(nvertsArray);
    jint *nverts = env->GetIntArrayElements(nvertsArray, 0);

    int vertsSize = env->GetArrayLength(vertsArray);
    jint *verts = env->GetIntArrayElements(vertsArray, 0);

    int pointsSize = env->GetArrayLength(pointsArray);
    int numPoints = pointsSize / numFloatsPerPoint;

    OsdMeshWrapperSharedPtr wrapper = NewWrapper();
    wrapper->CreateCatmarkMesh(level,
                      numPoints, numFloatsPerPoint,
                      nvertsSize, nverts, vertsSize, verts);

    env->ReleaseIntArrayElements(nvertsArray, nverts, 0);
    env->ReleaseIntArrayElements(vertsArray, verts, 0);

    return jint(wrapper->GetMeshHandleId());
}

JNIEXPORT void JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_UpdatePoints(
    JNIEnv * env, jclass, jint meshHandleId,
    jint level, jfloatArray pointsArray)
{
    int pointsSize = env->GetArrayLength(pointsArray);
    jfloat *points = env->GetFloatArrayElements(pointsArray, 0);

    OsdMeshWrapperSharedPtr wrapper = GetWrapper(meshHandleId);

    wrapper->UpdatePoints(level, points);

    env->ReleaseFloatArrayElements(pointsArray, points, 0);
}

JNIEXPORT void JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_DeleteMesh(
    JNIEnv * env, jclass, jint meshHandleId)
{
    DeleteWrapper(meshHandleId);
}

JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_GetVertexBufferId(
    JNIEnv * env, jclass, jint meshHandleId)
{
    OsdMeshWrapperSharedPtr wrapper = GetWrapper(meshHandleId);
    return jint(wrapper->GetVertexBufferId());
}

JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_GetTrianglesIndexBufferId(
    JNIEnv * env, jclass, jint meshHandleId)
{
    OsdMeshWrapperSharedPtr wrapper = GetWrapper(meshHandleId);
    return jint(wrapper->GetTrianglesIndexBufferId());
}

JNIEXPORT jint JNICALL Java_com_opensubdiv_OpenSubdivViewer_OpenSubdiv_GetTrianglesIndexCount(
    JNIEnv * env, jclass, jint meshHandleId)
{
    OsdMeshWrapperSharedPtr wrapper = GetWrapper(meshHandleId);
    return jint(wrapper->GetTrianglesIndexCount());
}
