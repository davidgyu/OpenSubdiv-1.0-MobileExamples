package com.opensubdiv.OpenSubdivViewer;

import android.app.Fragment;
import android.content.Context;
import android.opengl.GLSurfaceView;
import android.os.Bundle;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;


public class ViewportFragment extends Fragment {
	
    private GLSurfaceView mGLView;

    @Override
    public View onCreateView(LayoutInflater inflater,
                             ViewGroup container,
                             Bundle savedInstanceState) {
    mGLView = new ViewportSurfaceView(getActivity());
        return mGLView;
    }
}

class ViewportSurfaceView extends GLSurfaceView {

    private final ViewportRenderer mRenderer;

    public ViewportSurfaceView(Context context) {
        super(context);

        // Create an OpenGL ES 2.0 context.
        setEGLContextClientVersion(2);

        // Set the Renderer for drawing on the GLSurfaceView
        mRenderer = new ViewportRenderer();
        setRenderer(mRenderer);

        // Render the view only when there is a change in the drawing data
        setRenderMode(GLSurfaceView.RENDERMODE_WHEN_DIRTY);
    }

    private final float TOUCH_SCALE_FACTOR = 180.0f / 320;
    private boolean mIsFlipped;
    private float mPreviousX;
    private float mPreviousY;

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        // MotionEvent reports input details from the touch screen
        // and other input controls. In this case, you are only
        // interested in events where the touch position changed.

        float x = e.getX();
        float y = e.getY();

        switch (e.getAction()) {
            case MotionEvent.ACTION_DOWN:
                mIsFlipped = mRenderer.isFlipped();
                Log.d("isFlipped", "" + mIsFlipped);
                break;
                
            case MotionEvent.ACTION_MOVE:

                float dx = x - mPreviousX;
                float dy = y - mPreviousY;

                mRenderer.mAngleX += (dx) * TOUCH_SCALE_FACTOR;
                mRenderer.mAngleY -= (dy) * TOUCH_SCALE_FACTOR;

                // reverse direction of rotation above the mid-line
                if (y > getHeight() / 2) {
                  dx = dx * -1 ;
                }

                // reverse direction of rotation to left of the mid-line
                if (x < getWidth() / 2) {
                  dy = dy * -1 ;
                }

                mRenderer.mAngleZ += (dx + dy) * TOUCH_SCALE_FACTOR;

                requestRender();
                break;
        }

        mPreviousX = x;
        mPreviousY = y;
        return true;
    }
}
