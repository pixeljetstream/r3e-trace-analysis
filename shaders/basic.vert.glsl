#version 330

uniform mat4  viewProjTM;

layout(location=0) in vec3 attribPos;

void main() {
  gl_Position = viewProjTM * vec4(attribPos,1);
}