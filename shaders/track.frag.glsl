#version 430

layout(binding=3) uniform sampler1D texHeatMap;
uniform vec4  color;
uniform vec4  timestipple;
uniform vec2  timeclamp;

out layout(location=0,index=0) vec4 out_Color;

in Interpolant {
  float data;
  float time;
} IN;

void main() {
  if (!(timeclamp.x <= IN.time && IN.time <= timeclamp.y)){
    discard;
  }

  vec4  temp = texture(texHeatMap, IN.data);
  float periodic = fract(IN.time * timestipple.x + timestipple.y);
  float width = timestipple.z;
  float start = 0.5 - width * 0.5;
  float fuzz  = width * 0.01;
  float a = start;
  float b = start + width;
  // http://accad.osu.edu/~smay/RManNotes/RegularPatterns/transitions.html
  float fade  =  smoothstep(a - fuzz, a, periodic) - smoothstep(b, b + fuzz, periodic);
  
  a += width*0.2;
  b -= width*0.2;
  fuzz *= 10;
  float boost =  (1-(smoothstep(a - fuzz, a, periodic) - smoothstep(b, b + fuzz, periodic)));
  
  temp.xyz *= mix(vec3(1),temp.xyz+0.3, boost*(timestipple.w));
  temp.w   *= max(fade, 1-timestipple.w);
  
  temp.xyz  = mix(temp.xyz, color.xyz, color.w);
  
  out_Color = temp;
}