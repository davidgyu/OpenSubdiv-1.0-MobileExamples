//
//  Shader.vsh
//  OpenSubdivViewer
//
//  Created by David Yu on 8/12/12.
//  Copyright (c) 2012 Pixar Animation Studios. All rights reserved.
//

uniform mat4 ModelViewProjectionMatrix;

attribute vec4 position;

varying lowp vec4 C;

void main()
{
    gl_Position = ModelViewProjectionMatrix * position;
    C = vec4(1.0, 1.0, 0.0, 1.0);
}
