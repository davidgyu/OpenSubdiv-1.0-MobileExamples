package com.opensubdiv.OpenSubdivViewer;

import java.lang.Math;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.nio.ShortBuffer;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.opengl.Matrix;
import android.util.Log;

public class ViewportRenderer implements GLSurfaceView.Renderer {

    private static final String TAG = "ViewportRenderer";
    private Mesh mMesh;

    private final float[] mMVMatrix = new float[16];
    private final float[] mProjMatrix = new float[16];

    // Declare as volatile because we are updating it from another thread
    public volatile float mAngleX;
    public volatile float mAngleY;
    public volatile float mAngleZ;

    public static int GetInteger(int value) {
        IntBuffer paramsBuffer =
            ByteBuffer.allocateDirect(4)
                      .order(ByteOrder.nativeOrder())
                      .asIntBuffer();
        paramsBuffer.position(0);
        GLES20.glGetIntegerv(value, paramsBuffer);
        return paramsBuffer.get(0);
    }

    public static int GetBufferParameter(int target, int pname) {
        IntBuffer paramsBuffer =
            ByteBuffer.allocateDirect(4)
                      .order(ByteOrder.nativeOrder())
                      .asIntBuffer();
        paramsBuffer.position(0);
        GLES20.glGetBufferParameteriv(target, pname, paramsBuffer);
        return paramsBuffer.get(0);
    }

    public boolean isFlipped() {
        float[] m = new float[16];
        Matrix.setRotateM(m, 0, mAngleY, 1.0f, 0.0f, 0.0f);
        Matrix.rotateM(m, 0, mAngleX, 0.0f, 1.0f, 0.0f);
        return (m[2]+m[6]+m[10] < 0.0);
        //return (m[8]+m[9]+m[10] < 0.0);
    }

    public void onSurfaceCreated(GL10 unused, EGLConfig config) {

    	Log.d("extensions:", GLES20.glGetString(GLES20.GL_EXTENSIONS));
    	
        GLES20.glClearColor(0.2f, 0.2f, 0.3f, 1.0f);
        GLES20.glLineWidth(2.0f);

        mMesh = new Mesh();
    }

    public void onDrawFrame(GL10 unused) {

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT | GLES20.GL_DEPTH_BUFFER_BIT);

        GLES20.glEnable(GLES20.GL_DEPTH_TEST);

        Matrix.setLookAtM(mMVMatrix, 0, 0, 0, -4, 0f, 0f, 0f, 0f, 1.0f, 0.0f);

        Matrix.rotateM(mMVMatrix, 0, mAngleY, 1.0f, 0.0f, 0.0f);
        Matrix.rotateM(mMVMatrix, 0, mAngleX, 0.0f, 1.0f, 0.0f);

        mMesh.draw(mMVMatrix, mProjMatrix);
    }

    public void onSurfaceChanged(GL10 unused, int width, int height) {
        GLES20.glViewport(0, 0, width, height);

        float ratio = (float) width / height;
        float dx = 0.5f * ratio;
        float dy = 0.5f;

        Matrix.frustumM(mProjMatrix, 0, -dx, dx, -dy, dy, 1, 10);
    }

    public static int loadShader(int type, String shaderCode){

        int shader = GLES20.glCreateShader(type);

        GLES20.glShaderSource(shader, shaderCode);
        GLES20.glCompileShader(shader);
        String infoLog = GLES20.glGetShaderInfoLog(shader);
        if (!infoLog.isEmpty()) {
            Log.d("compile shader:", infoLog);
        }

        return shader;
    }

    /**
     * Utility method for debugging OpenGL calls. Provide the name of the call
     * just after making it:
     *
     * <pre>
     * mColorHandle = GLES20.glGetUniformLocation(mProgram, "vColor");
     * ViewportRenderer.checkGlError("glGetUniformLocation");</pre>
     *
     * If the operation is not successful, the check throws an error.
     *
     * @param glOperation - Name of the OpenGL call to check.
     */
    public static void checkGlError(String glOperation) {
        int error;
        while ((error = GLES20.glGetError()) != GLES20.GL_NO_ERROR) {
            Log.e(TAG, glOperation + ": glError " + error);
            throw new RuntimeException(glOperation + ": glError " + error);
        }
    }
}

class Mesh {

    private final String lightingShaderCode =
"                                                                          \n" +
"#define NUM_LIGHTS 1                                                      \n" +
"                                                                          \n" +
"struct LightSource {                                                      \n" +
"    vec4 position;                                                        \n" +
"    vec4 ambient;                                                         \n" +
"    vec4 diffuse;                                                         \n" +
"    vec4 specular;                                                        \n" +
"    vec3 attenuation;                                                     \n" +
"    vec3 spotDirection;                                                   \n" +
"    float spotExponent;                                                   \n" +
"    float spotCosCutoff;                                                  \n" +
"};                                                                        \n" +
"                                                                          \n" +
"uniform LightSource lightSource[NUM_LIGHTS];                              \n" +
"                                                                          \n" +
"vec4                                                                      \n" +
"lighting(vec3 Peye, vec3 Neye, vec4 Cdiffuse)                             \n" +
"{                                                                         \n" +
"    vec4 Cmaterial = vec4(0.8, 0.8, 0.8, 1.0);                            \n" +
"    float shininess = 100.0;                                              \n" +
"                                                                          \n" +
"    vec4 color = vec4(0.0);                                               \n" +
"                                                                          \n" +
"    for (int i = 0; i < NUM_LIGHTS; ++i) {                                \n" +
"                                                                          \n" +
"        vec4 Plight = lightSource[i].position;                            \n" +
"        vec3 L = Plight.xyz - Peye.xyz*Plight.w;                          \n" +
"        float dist = length(L)*Plight.w;                                  \n" +
"        L = normalize(L);                                                 \n" +
"                                                                          \n" +
"        vec3 N = normalize(Neye);                                         \n" +
"        vec3 V = Peye.xyz;                                                \n" +
"        vec3 H = normalize(L + V);                                        \n" +
"                                                                          \n" +
"        float d = max(0.0, dot(N, L));                                    \n" +
"        float s = pow(max(0.0, dot(N, H)), shininess);                    \n" +
"                                                                          \n" +
"        float cosCutoff = lightSource[i].spotCosCutoff;                   \n" +
"        float cosTheta = dot(-L, normalize(lightSource[i].spotDirection));\n" +
"        float spot = pow(cosTheta, lightSource[i].spotExponent);          \n" +
"        spot = max(0.0, spot * step(cosCutoff, cosTheta));                \n" +
"        spot = mix(spot, 1.0, max(-cosCutoff, 0.0));                      \n" +
"                                                                          \n" +
"        float att = 1.0 / (lightSource[i].attenuation[0] +                \n" +
"                           lightSource[i].attenuation[1] * dist +         \n" +
"                           lightSource[i].attenuation[2] * dist*dist);    \n" +
"                                                                          \n" +
"        color += att * spot                                               \n" +
"                 * ( lightSource[i].ambient * Cmaterial                   \n" +
"                   + lightSource[i].diffuse * d * Cdiffuse                \n" +
"                   + lightSource[i].specular * s);                        \n" +
"    }                                                                     \n" +
"                                                                          \n" +
"    color.a = 1.0;                                                        \n" +
"    return color;                                                         \n" +
"}";

    private final String vertexShaderCode =
        "uniform mat4 uMVPMatrix;" +
        "uniform mat4 uMVMatrix;" +
        "uniform mat4 uMVNormalMatrix;" +

        "attribute vec4 vertex;" +
        "attribute vec3 normal;" +
        "attribute vec4 color;" +

        "varying vec3 Peye;" +
        "varying vec3 Neye;" +
        "varying vec4 C;" +

        "void main() {" +
        "  gl_Position = uMVPMatrix * vertex;" +
        "  Peye = (uMVMatrix * vertex).xyz;" +
        "  Neye = (uMVNormalMatrix * vec4(normal,1.0)).xyz;" +
        "  C = color;" +
        "}";

    private final String fragmentShaderCode =
        "precision mediump float;" +

        "varying vec3 Peye;" +
        "varying vec3 Neye;" +
        "varying vec4 C;" +

        lightingShaderCode + 

        "void main() {" +
        "  gl_FragColor = lighting(Peye, Neye, C);" +
        "}";

    private final String hullVertexShaderCode =
        "uniform mat4 uMVPMatrix;" +

        "attribute vec4 vertex;" +

        "varying vec4 C;" +

        "void main() {" +
        "  gl_Position = uMVPMatrix * vertex;" +
        "  C = vec4(1.0, 1.0, 0.0, 1.0);" +
        "}";

    private final String hullFragmentShaderCode =
        "precision mediump float;" +
        "varying vec4 C;" +

        "void main() {" +
        "  gl_FragColor = C;" +
        "}";

    private final int mSurfaceProgram;
    private final int mHullProgram;
    private final int meshHandle;

    private final int level = 3;

    static final int COORDS_PER_VERTEX = 3;
    static final int COORDS_PER_NORMAL = 3;
    static float points[];
    static int nverts[];
    static int verts[];

    private final float meshColor[] = { 0.2f, 0.2f, 0.8f, 1.0f };
    private final float hullColor[] = { 1.0f, 1.0f, 0.0f, 1.0f };

    private int hullVertexBuffer = 0;
    private int hullIndexBuffer = 0;

    void buildHull() {
        int buf[] = { 0, 0 };
        GLES20.glGenBuffers(2, buf, 0);
        hullVertexBuffer = buf[0];
        hullIndexBuffer = buf[1];

        FloatBuffer vertexBuffer =
            ByteBuffer.allocateDirect(points.length * 4)
                      .order(ByteOrder.nativeOrder())
                      .asFloatBuffer();
        vertexBuffer.put(points);
        vertexBuffer.position(0);

        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, hullVertexBuffer);
        GLES20.glBufferData(GLES20.GL_ARRAY_BUFFER,
                            points.length * 4, vertexBuffer,
                            GLES20.GL_STATIC_DRAW);
        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, 0);

        short hullVerts[] = new short[verts.length * 2];
        int voffset = 0;
        for (int i=0; i<nverts.length; ++i) {
            int nv = nverts[i];
            for (int j=0; j<nv; ++j) {
               hullVerts[2*(voffset+j)] = (short) verts[voffset+j];
               hullVerts[2*(voffset+j)+1] = (short) verts[voffset+((j+1) % nv)];
            }
            voffset += nv;
        }
        ShortBuffer indexBuffer =
            ByteBuffer.allocateDirect(hullVerts.length * 2)
                      .order(ByteOrder.nativeOrder())
                      .asShortBuffer();
        indexBuffer.put(hullVerts);
        indexBuffer.position(0);

        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, hullIndexBuffer);
        GLES20.glBufferData(GLES20.GL_ELEMENT_ARRAY_BUFFER,
                            hullVerts.length * 2, indexBuffer,
                            GLES20.GL_STATIC_DRAW);
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    public void drawHull(float[] mvMatrix, float[] pMatrix) {
        GLES20.glUseProgram(mHullProgram);
        bindTransform(mHullProgram, mvMatrix, pMatrix);

        int mColorHandle = GLES20.glGetAttribLocation(mHullProgram, "color");
        GLES20.glVertexAttrib4f(mColorHandle,
            hullColor[0], hullColor[1], hullColor[2], hullColor[3]);

        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, hullVertexBuffer);
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, hullIndexBuffer);

        int mPositionHandle = GLES20.glGetAttribLocation(mHullProgram, "vertex");
        GLES20.glEnableVertexAttribArray(mPositionHandle);
        GLES20.glVertexAttribPointer(mPositionHandle, COORDS_PER_VERTEX,
                                     GLES20.GL_FLOAT, false,
                                     3*4, 0);

        GLES20.glDrawElements(GLES20.GL_LINES,
                              verts.length * 2,
                              GLES20.GL_UNSIGNED_SHORT, 0);

        GLES20.glDisableVertexAttribArray(mPositionHandle);
        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, 0);
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    public void bindTransform(int program, float[] mvMatrix, float[] pMatrix) {
        float[] mvpMatrix = new float[16];
        Matrix.multiplyMM(mvpMatrix, 0, pMatrix, 0, mvMatrix, 0);
        float[] mInvMatrix = new float[16];
        float[] mvpNormalMatrix = new float[16];
        Matrix.invertM(mInvMatrix, 0, mvMatrix, 0);
        Matrix.transposeM(mvpNormalMatrix, 0, mInvMatrix, 0);

        int mvp = GLES20.glGetUniformLocation(program, "uMVPMatrix");
        if (mvp >= 0)
            GLES20.glUniformMatrix4fv(
                    mvp, 1, false, mvpMatrix, 0);
        int mv = GLES20.glGetUniformLocation(program, "uMVMatrix");
        if (mv >= 0)
            GLES20.glUniformMatrix4fv(
                    mv, 1, false, mvMatrix, 0);
        int mvn = GLES20.glGetUniformLocation(program, "uMVNormalMatrix");
        if (mvn >= 0)
            GLES20.glUniformMatrix4fv(
                    mvn, 1, false, mvpNormalMatrix, 0);
    }

    public void bindLighting(int program) {
        float pos[] = { 0.0f, 0.0f, -1.0f, 0.0f };
        GLES20.glUniform4fv(GLES20.glGetUniformLocation(program,
                "lightSource[0].position"), 1, pos, 0);

        float amb[] = { 0.2f, 0.2f, 0.2f, 0.0f };
        GLES20.glUniform4fv(GLES20.glGetUniformLocation(program,
                "lightSource[0].ambient"), 1, amb, 0);

        float diff[] = { 0.8f, 0.8f, 0.8f, 0.0f };
        GLES20.glUniform4fv(GLES20.glGetUniformLocation(program,
                "lightSource[0].diffuse"), 1, diff, 0);

        float spec[] = { 0.8f, 0.8f, 0.8f, 0.0f };
        GLES20.glUniform4fv(GLES20.glGetUniformLocation(program,
                "lightSource[0].specular"), 1, spec, 0);

        float att[] = { 1.0f, 0.0f, 0.0f };
        GLES20.glUniform3fv(GLES20.glGetUniformLocation(program,
                "lightSource[0].attenuation"), 1, att, 0);

        float spotDir[] = { 0.0f, 0.0f, 1.0f };
        GLES20.glUniform3fv(GLES20.glGetUniformLocation(program,
                "lightSource[0].spotDirection"), 1, spotDir, 0);

        GLES20.glUniform1f(GLES20.glGetUniformLocation(program,
                "lightSource[0].spotExponent"), 0.0f);

        GLES20.glUniform1f(GLES20.glGetUniformLocation(program,
                "lightSource[0].spotCosCutoff"), -1.0f);
    }

    void buildCube() {
        float pointsCube[] = {
            1.0f, 1.0f, 1.0f,
           -1.0f, 1.0f, 1.0f,
           -1.0f,-1.0f, 1.0f,
            1.0f,-1.0f, 1.0f,

           -1.0f,-1.0f,-1.0f,
           -1.0f, 1.0f,-1.0f,
            1.0f, 1.0f,-1.0f,
            1.0f,-1.0f,-1.0f,
        };

        int nvertsCube[] = {
            4, 4, 4, 4, 4, 4,
        };

        int vertsCube[] = {
            0, 1, 2, 3,
            4, 5, 6, 7,

            0, 3, 7, 6,
            4, 2, 1, 5,

            0, 6, 5, 1,
            4, 7, 3, 2,
        };

        points = pointsCube;
        nverts = nvertsCube;
        verts = vertsCube;
    }

    void buildTorus() {
        int numSlices = 4;
        int numStacks = 8;
        float majorRadius = 1.0f;
        float minorRadius = 0.5f;

        points = new float[3 * numSlices * numStacks];
        nverts = new int[numSlices * numStacks];
        verts = new int[4 * numSlices * numStacks];

        for (int i=0; i<numStacks; ++i) {
            double a0 = i * 2.0 * Math.PI / numStacks
                        + Math.PI / numStacks;
            double x = Math.cos(a0);
            double y = Math.sin(a0);

            for (int j=0; j<numSlices; ++j) {
                double a1 = j * 2.0 * Math.PI / numSlices
                            + Math.PI / numSlices;
                double r = minorRadius * Math.cos(a1) + majorRadius;
                double z = minorRadius * Math.sin(a1);

                int pointOffset = i * numSlices + j;
                points[pointOffset*3+0] = (float) (x * r);
                points[pointOffset*3+1] = (float) (y * r);
                points[pointOffset*3+2] = (float) (z);

                int primOffset = i * numSlices + j;
                int vertBase = 4 * primOffset;
                int pointBase = primOffset;

                int sliceOffset =
                    j < numSlices-1
                            ? 1
                            : 1-numSlices;
                int stackOffset =
                    i < numStacks-1
                            ? numSlices
                            : numSlices-(numStacks * numSlices);

                verts[vertBase + 3] = pointBase;
                verts[vertBase + 2] = pointBase + sliceOffset;
                verts[vertBase + 1] = pointBase + sliceOffset + stackOffset;
                verts[vertBase + 0] = pointBase               + stackOffset;
                nverts[primOffset] = 4;
            }
        }
    }

    public Mesh() {
        int vertexShader = ViewportRenderer.loadShader(
                GLES20.GL_VERTEX_SHADER, vertexShaderCode);
        int fragmentShader = ViewportRenderer.loadShader(
                GLES20.GL_FRAGMENT_SHADER, fragmentShaderCode);

        mSurfaceProgram = GLES20.glCreateProgram();
        GLES20.glAttachShader(mSurfaceProgram, vertexShader);
        GLES20.glAttachShader(mSurfaceProgram, fragmentShader);
        GLES20.glLinkProgram(mSurfaceProgram);

        vertexShader = ViewportRenderer.loadShader(
                GLES20.GL_VERTEX_SHADER, hullVertexShaderCode);
        fragmentShader = ViewportRenderer.loadShader(
                GLES20.GL_FRAGMENT_SHADER, hullFragmentShaderCode);

        mHullProgram = GLES20.glCreateProgram();
        GLES20.glAttachShader(mHullProgram, vertexShader);
        GLES20.glAttachShader(mHullProgram, fragmentShader);
        GLES20.glLinkProgram(mHullProgram);

        //buildCube();
        buildTorus();

        buildHull();

        meshHandle = OpenSubdiv.CreateCatmarkMesh(
                level, nverts, verts, COORDS_PER_VERTEX, points);
        OpenSubdiv.UpdatePoints(meshHandle, level, points);

        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER,
                            OpenSubdiv.GetVertexBufferId(meshHandle));
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, 
                            OpenSubdiv.GetTrianglesIndexBufferId(meshHandle));

    	Log.d("max texture size:", "" +
            ViewportRenderer.GetInteger(GLES20.GL_MAX_TEXTURE_SIZE));
    	Log.d("max vertex texture image units:", "" +
            ViewportRenderer.GetInteger(GLES20.GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS));

        Log.d("mesh triangles points", "" +
            ViewportRenderer.GetBufferParameter(GLES20.GL_ARRAY_BUFFER, GLES20.GL_BUFFER_SIZE));
        Log.d("mesh triangles indices", "" +
            ViewportRenderer.GetBufferParameter(GLES20.GL_ELEMENT_ARRAY_BUFFER, GLES20.GL_BUFFER_SIZE));
        Log.d("mesh triangles vertices", "" +
            OpenSubdiv.GetTrianglesIndexCount(meshHandle));

        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, 0);
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    public void drawSurface(float[] mvMatrix, float[] pMatrix) {
        GLES20.glUseProgram(mSurfaceProgram);
        bindTransform(mSurfaceProgram, mvMatrix, pMatrix);

        bindLighting(mSurfaceProgram);

        int mColorHandle = GLES20.glGetAttribLocation(mSurfaceProgram, "color");
        GLES20.glVertexAttrib4f(mColorHandle,
            meshColor[0], meshColor[1], meshColor[2], meshColor[3]);

        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER,
                            OpenSubdiv.GetVertexBufferId(meshHandle));
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, 
                            OpenSubdiv.GetTrianglesIndexBufferId(meshHandle));

        int mPositionHandle = GLES20.glGetAttribLocation(mSurfaceProgram, "vertex");
        GLES20.glEnableVertexAttribArray(mPositionHandle);
        GLES20.glVertexAttribPointer(mPositionHandle, COORDS_PER_VERTEX,
                                     GLES20.GL_FLOAT, false,
                                     6*4, 0);

        int mNormalHandle = GLES20.glGetAttribLocation(mSurfaceProgram, "normal");
        GLES20.glEnableVertexAttribArray(mNormalHandle);
        GLES20.glVertexAttribPointer(mNormalHandle, COORDS_PER_NORMAL,
                                     GLES20.GL_FLOAT, false,
                                     6*4, 3*4);

        GLES20.glDrawElements(GLES20.GL_TRIANGLES,
                              OpenSubdiv.GetTrianglesIndexCount(meshHandle),
                              GLES20.GL_UNSIGNED_SHORT, 0);

        GLES20.glDisableVertexAttribArray(mPositionHandle);
        GLES20.glDisableVertexAttribArray(mNormalHandle);
        GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, 0);
        GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    public void draw(float[] mvMatrix, float[] pMatrix) {
        drawHull(mvMatrix, pMatrix);
        drawSurface(mvMatrix, pMatrix);
    }
}

