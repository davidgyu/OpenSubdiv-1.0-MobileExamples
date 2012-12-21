package com.opensubdiv.OpenSubdivViewer;

public class OpenSubdiv {

     static {
         System.loadLibrary("gnustl_shared");
         System.loadLibrary("osdCPU");
         System.loadLibrary("osdGPU");
         System.loadLibrary("OpenSubdivjni");
     }

     public static native int CreateCatmarkMesh(
        int level, int[] nverts, int[] verts,
        int numFloatsPerPoint, float[] points);

     public static native void UpdatePoints(
        int meshHandleId, int level, float[] points);

     public static native int GetVertexBufferId(int meshHandleId);

     public static native int GetTrianglesIndexBufferId(int meshHandleId);

     public static native int GetTrianglesIndexCount(int meshHandleId);
}
