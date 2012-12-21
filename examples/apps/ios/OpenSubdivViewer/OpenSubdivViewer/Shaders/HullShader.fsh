//
//  Shader.fsh
//  OpenSubdivViewer
//
//  Created by David Yu on 8/12/12.
//  Copyright (c) 2012 Pixar Animation Studios. All rights reserved.
//

varying lowp vec4 C;

void main()
{
    gl_FragColor = C;
}
