//
//  Shader.fsh
//  OpenSubdivViewer
//
//  Created by David Yu on 8/12/12.
//  Copyright (c) 2012 Pixar Animation Studios. All rights reserved.
//

precision mediump float;

#define NUM_LIGHTS 1

struct LightSource {
    vec4 position;
    vec4 ambient;
    vec4 diffuse;
    vec4 specular;
    vec3 attenuation;
    vec3 spotDirection;
    float spotExponent;
    float spotCosCutoff;
};

uniform LightSource lightSource[NUM_LIGHTS];

vec4
lighting(vec3 Peye, vec3 Neye, vec4 Cdiffuse)
{
    vec4 Cmaterial = vec4(0.8, 0.8, 0.8, 1.0);
    float shininess = 100.0;

    vec4 color = vec4(0.0);

    for (int i = 0; i<NUM_LIGHTS; ++i) {
        vec4 Plight = lightSource[i].position;
        vec3 L = Plight.xyz - Peye.xyz*Plight.w;
        float dist = length(L)*Plight.w;
        L = normalize(L);

        vec3 N = normalize(Neye);
        vec3 V = Peye.xyz;
        vec3 H = normalize(L + V);

        float d = max(0.0, dot(N, L));
        float s = pow(max(0.0, dot(N, H)), shininess);

        float cosCutoff = lightSource[i].spotCosCutoff;
        float cosTheta = dot(-L, normalize(lightSource[i].spotDirection));
        float spot = pow(cosTheta, lightSource[i].spotExponent);
        spot = max(0.0, spot * step(cosCutoff, cosTheta));
        spot = mix(spot, 1.0, max(-cosCutoff, 0.0));

        float att = 1.0 / (lightSource[i].attenuation[0] +
                           lightSource[i].attenuation[1] * dist +
                           lightSource[i].attenuation[2] * dist*dist);

        color += att * spot
                 * ( lightSource[i].ambient * Cmaterial
                   + lightSource[i].diffuse * d * Cdiffuse
                   + lightSource[i].specular * s);
    }

    color.a = 1.0;
    return color;
}

varying vec3 Peye;
varying vec3 Neye;
varying vec4 C;

void main() {
    gl_FragColor = lighting(Peye, Neye, C);
}
