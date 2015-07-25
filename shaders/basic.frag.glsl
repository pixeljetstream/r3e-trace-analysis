#version 430

uniform vec4     color;

out layout(location=0,index=0) vec4 out_Color;

void main() {
  out_Color = color;
}