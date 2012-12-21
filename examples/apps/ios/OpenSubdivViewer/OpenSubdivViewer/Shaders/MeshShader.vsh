//
//  Shader.vsh
//  OpenSubdivViewer
//
//  Created by David Yu on 8/12/12.
//  Copyright (c) 2012 Pixar Animation Studios. All rights reserved.
//

precision mediump float;

uniform mat4 ModelViewMatrix;
uniform mat4 ModelViewProjectionMatrix;
uniform mat4 ModelViewInverseMatrix;

attribute vec4 position;
attribute vec3 normal;
attribute vec4 color;

varying vec3 Peye;
varying vec3 Neye;
varying vec4 C;

void main() {
    gl_Position = ModelViewProjectionMatrix * position;
    Peye = (ModelViewMatrix * position).xyz;
    Neye = (ModelViewMatrix * vec4(normal,0)).xyz;
    C = color;
}
