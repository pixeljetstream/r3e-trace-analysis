#version 430

uniform mat4  viewProjTM;
uniform mat4  dataTM;
uniform float width;
uniform float shift;
uniform int   numPoints;

layout(binding=0) uniform samplerBuffer texPos;
layout(binding=1) uniform samplerBuffer texData;
layout(binding=2) uniform samplerBuffer texTime;

out Interpolant {
  float data;
  float time;
  float side;
} OUT;

void main() {
  int  idx     = gl_VertexID/2;
  vec3 pos     = texelFetch(texPos, idx).xyz;
  vec3 posNext = texelFetch(texPos, min(idx + 1, numPoints-1)).xyz;
  vec3 posPrev = texelFetch(texPos, max(0,idx - 1)).xyz;

  vec3 delta   = posNext - posPrev;
  float len    = length(delta);
  vec3 tangent = len > 0.0000001 ? delta/len : vec3(0,0,0);
  vec3 normal  = normalize(cross(tangent,vec3(0,0,1)));
  
  pos += normal * shift;
  
  float side = float(gl_VertexID % 2)*2 - 1;
  normal *= side;
  pos += normal * width;
    
  
  vec4 data = vec4(texelFetch(texData, idx).r, 0,0,1);
  OUT.data = (dataTM * data).x;
  OUT.time = texelFetch(texTime, idx).r;
  OUT.side = side;

  gl_Position = viewProjTM * vec4(pos,1);
}