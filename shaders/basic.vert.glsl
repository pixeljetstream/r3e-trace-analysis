#version 430

uniform mat4  viewProjTM;

in layout(location=0) vec3  attribPos;

void main() {
  gl_Position = viewProjTM * vec4(attribPos,1);
}