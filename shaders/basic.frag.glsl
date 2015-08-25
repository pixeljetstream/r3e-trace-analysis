#version 330

uniform vec4     color;

layout(location=0,index=0) out vec4 out_Color;

void main() {
  out_Color = color;
}