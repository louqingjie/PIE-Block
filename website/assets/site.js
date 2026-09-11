/* PIE-Block 介绍页交互
   背景动效（hero 流体 + 点阵网格）、生成结果面板的页签、复制按钮、
   滚动揭示。
   无依赖；prefers-reduced-motion 下只画一帧静态图。 */
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  /* ==========================================================
     流体背景
     两遍渲染：
       1) flowmap —— 1/N 分辨率的离屏 ping-pong 纹理，只做「衰减 + 盖章」。
          R 通道存这块地方被搅动的强度，G/B 通道用 0.5 为中心的有符号
          编码存当时的搅动方向。
       2) 显示 —— 全分辨率，采样 flowmap 得到 influence 与方向，据此
          扭曲噪声场的采样坐标，再调色、加辉光、加颗粒与暗角。
     技术上属于常见做法（flowmap 痕迹 + 域扭曲 + simplex 噪声），这里按
     PIE-Block 的品牌色重写了一份。
     ========================================================== */

  const FLUID_VERT = `#version 300 es
in vec2 a_position;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

  /* 第一遍：衰减 + 高斯盖章 */
  const FLUID_FLOW_FRAG = `#version 300 es
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform sampler2D u_prev;
uniform vec2  u_pointer;
uniform vec2  u_velocity;
uniform float u_radius;
uniform float u_strength;
uniform float u_decay;
out vec4 outState;

void main() {
  vec2 uv = gl_FragCoord.xy / vec2(textureSize(u_prev, 0));
  vec4 state = texture(u_prev, uv);

  // 旧痕迹逐帧衰减，方向信息同时回中，避免留下静止的残留方向
  state.r  *= u_decay;
  state.gb  = mix(vec2(0.5), state.gb, u_decay);

  float d = distance(uv, u_pointer);
  float brush = exp(-(d * d) / (u_radius * u_radius * 0.5));
  brush = max(0.0, brush - 0.01);

  // 停着也留痕，快速划动时更强
  float speed = length(u_velocity);
  float strength = u_strength * (0.3 + min(speed * 3.0, 0.7));

  float blend = brush * min(strength, 0.4) * 0.3;
  float next = max(state.r, brush * strength);

  state.r = next;
  state.g = mix(state.g, clamp(u_velocity.x * 2.0 + 0.5, 0.0, 1.0), blend);
  state.b = mix(state.b, clamp(u_velocity.y * 2.0 + 0.5, 0.0, 1.0), blend);

  outState = state;
}
`;

  /* 第二遍：流体显示 */
  const FLUID_DRAW_FRAG = `#version 300 es
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform sampler2D u_flow;
uniform vec2  u_resolution;
uniform float u_time;
uniform float u_scale;
uniform vec2  u_offset;
uniform vec3  u_c1, u_c2, u_c3, u_c4, u_c5;
uniform float u_flowDistort;
uniform float u_flowSwirl;
uniform float u_grain;
uniform vec3  u_glowA, u_glowB, u_glowC;
uniform float u_glow;
uniform vec2  u_light;
uniform float u_lightCore;
uniform float u_lightHalo;
uniform float u_vignette;
uniform float u_bloomThreshold;
uniform float u_bloomRange;
uniform float u_bloomStrength;
out vec4 fragColor;

/* 3D simplex noise —— Ashima Arts / Stefan Gustavson 实现，MIT 许可 */
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
  const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

  vec3 i  = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);

  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);

  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;

  i = mod289(i);
  vec4 p = permute(permute(permute(
             i.z + vec4(0.0, i1.z, i2.z, 1.0))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0))
           + i.x + vec4(0.0, i1.x, i2.x, 1.0));

  float n_ = 0.142857142857;
  vec3 ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);

  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);

  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);

  vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

  vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
  m = m * m;
  return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// 单倍频即可：下面的两级域扭曲已经提供了足够的细节层次。
// 想更碎可以调大 OCTAVES，代价是每个像素多一次 snoise。
#define OCTAVES 1

float fbm(vec3 p) {
  float sum = 0.0;
  float amp = 0.6;
  for (int i = 0; i < OCTAVES; i++) {
    sum += amp * snoise(p);
    p = p * 2.0 + 100.0;
    amp *= 0.4;
  }
  return sum;
}

// 两级域扭曲：先用一层噪声算位移，再用位移后的坐标算第二层
float fluidField(vec2 q, float t) {
  vec2 warp1 = vec2(
    fbm(vec3(q * 0.6, t * 0.06)),
    fbm(vec3(q * 0.6 + 5.2, t * 0.06 + 1.3))
  ) * 0.6;

  vec2 warp2 = vec2(
    fbm(vec3((q + warp1) * 0.7 + 1.7, t * 0.05 + 3.1)),
    fbm(vec3((q + warp1) * 0.7 + 9.2, t * 0.05 + 5.7))
  ) * 0.5;

  return fbm(vec3((q + warp1 + warp2) * 0.5, t * 0.04));
}

// 中心差分求噪声梯度，当作无散度的伪 curl 用，负责把直线流动掰弯
vec2 curl(vec2 q, float t) {
  const float e = 0.02;
  float n  = snoise(vec3(q * 0.8, t));
  float nx = snoise(vec3((q + vec2(e, 0.0)) * 0.8, t));
  float ny = snoise(vec3((q + vec2(0.0, e)) * 0.8, t));
  return vec2(-(ny - n), (nx - n)) / e * 0.003;
}

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  float aspect = u_resolution.x / u_resolution.y;
  vec2 uv = gl_FragCoord.xy / u_resolution;

  vec4 state = texture(u_flow, uv);
  float influence = state.r;
  vec2 dir = (state.gb - 0.5) * 2.0;

  vec2 anchor = vec2(uv.x * aspect, uv.y) * u_scale;
  vec2 q = anchor + u_offset;

  // 1) 按当初划过的方向把采样坐标推开
  q += dir * influence * u_flowDistort * 0.8;

  // 2) 围绕指针所在的基准点做局部旋转，越靠近中心转得越狠
  float angle = influence * u_flowSwirl * 2.5;
  float ca = cos(angle);
  float sa = sin(angle);
  vec2 delta = q - anchor;
  q += (mat2(ca, sa, -sa, ca) * delta - delta) * influence;

  // 3) 域扭曲后的噪声场
  float t = u_time;
  vec2 warped = q + curl(q, t * 0.04) * 12.0;
  float field = fluidField(warped, t);
  float swirl = snoise(vec3(warped * 0.8 + field * 1.5, t * 0.035)) * 0.5 + 0.5;

  float n = field * 0.5 + 0.5;
  vec3 col = mix(u_c1, u_c2, smoothstep(0.20, 0.50, n));
  col = mix(col, u_c3, smoothstep(0.35, 0.65, n + swirl * 0.25));
  col = mix(col, u_c4, smoothstep(0.60, 0.85, swirl) * 0.55);
  col = mix(col, u_c5, smoothstep(0.50, 0.80, n * swirl) * 0.35);

  // 4) 被搅动过的地方浮出三色辉光，用噪声调制混合比例。
  // 两次 mix 的比例都取 influence 的 smoothstep，不是 influence 本身：
  // 后者是线性上升，痕迹边缘会拖出一条生硬的过渡带。
  float glow = smoothstep(0.0, 0.8, influence);
  float glowNoise = snoise(vec3(warped * 1.5, t * 0.08)) * 0.5 + 0.5;
  float glowDist = smoothstep(0.0, 1.0, influence);
  vec3 glowMix = mix(u_glowC, u_glowB, glowDist);
  glowMix = mix(glowMix, u_glowA, glowDist * glowNoise);
  col = mix(col, glowMix, glow * u_glow);

  // 颗粒：坐标跟着流动走，所以噪点是「浮」在流体上的
  if (u_grain > 0.0) {
    vec2 flowOffset = (warped - q) * u_resolution.y;
    vec2 gp = floor((gl_FragCoord.xy + flowOffset) / 5.0);
    col += (hash(gp) * 2.0 - 1.0) * u_grain;
  }

  // 自发光：亮的流体区域自己成为光源，辉光跟着流动走而不是固定在某处
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  float bloom = smoothstep(
    u_bloomThreshold - u_bloomRange,
    u_bloomThreshold + u_bloomRange,
    luma
  );
  col += (col * 0.85 + vec3(0.15, 0.145, 0.13)) * bloom * u_bloomStrength;

  // 虚拟光源：暖芯 + 冷晕，位置跟着指针走
  float ld = length((uv - u_light) * vec2(aspect, 1.0));
  col += vec3(1.0, 0.97, 0.9) * exp(-ld * ld * 4.5) * u_lightCore;
  col += vec3(0.72, 0.80, 1.0) * exp(-ld * 1.8) * u_lightHalo;

  // 暗角
  float vig = 1.0 - smoothstep(0.35, 0.75, length(uv - 0.5));
  col = mix(col * (1.0 - u_vignette), col, vig);

  // 量化前抖动。光源、暗角、bloom 都是跨度很大的平滑渐变，直接写进 8 位
  // 缓冲会在暗部留下一圈圈等值线（色带）。补一层 ±1 LSB 白噪声把台阶打散：
  // 单像素看不出来，色带会消失。参考页没做这一步，它的暗部同样有色带。
  col += (hash(gl_FragCoord.xy * 1.37) - 0.5) * (2.0 / 255.0);

  fragColor = vec4(col, 1.0);
}
`;

  function compile(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader;
    console.error("PIE-Block 着色器编译失败:", gl.getShaderInfoLog(shader));
    gl.deleteShader(shader);
    return null;
  }

  function buildProgram(gl, vertexSource, fragmentSource) {
    const vs = compile(gl, gl.VERTEX_SHADER, vertexSource);
    const fs = compile(gl, gl.FRAGMENT_SHADER, fragmentSource);
    if (!vs || !fs) return null;

    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.deleteShader(vs);
    gl.deleteShader(fs);

    if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program;
    console.error("PIE-Block 着色器链接失败:", gl.getProgramInfoLog(program));
    return null;
  }

  const FLOW_STATE = new Uint8Array([0, 128, 128, 255]);

  function createTarget(gl, width, height) {
    const data = new Uint8Array(width * height * 4);
    for (let i = 0; i < width * height; i++) {
      data[i * 4] = FLOW_STATE[0];
      data[i * 4 + 1] = FLOW_STATE[1];
      data[i * 4 + 2] = FLOW_STATE[2];
      data[i * 4 + 3] = FLOW_STATE[3];
    }

    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    const framebuffer = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);

    return { framebuffer, texture, width, height };
  }

  function createFluid(canvas, options) {
    if (!canvas) return;

    const opt = Object.assign(
      {
        // 调色沿用参考页的明度结构（近黑 / 深色 / 中调 / 亮暖点缀 / 近黑），
        // 只把色相换到品牌青。明度结构决定观感，换色相不会跑味。
        colors: ["#010305", "#0f3a4a", "#14536b", "#efd0b4", "#010305"],
        glowColors: ["#e9fffb", "#57d6e8", "#1b6f85"],
        scale: 1.77,
        // 参考页的单位是「百分之一」，进 uniform 前除以 100。
        // 这两个数决定噪声场被采样的是哪一块区域，差一个量级就完全是另一幅图案。
        offsetX: -124,
        offsetY: -48,
        speed: 28,
        // flowmap 参数（参考页原值）
        flowScale: 4,
        decay: 0.925,
        mouseRadius: 0.09,
        mouseStrength: 1.8,
        mouseSmoothing: 0.1,
        mouseVelocity: 0.2,
        // 显示参数（参考页原值）
        distortBoost: 2.2,
        // 满 influence 时约 2 弧度的差动旋转。参考页在 Windows 与触屏上不注册
        // 鼠标，这条路径只有 mac / Linux 会跑到。
        swirlBoost: 0.8,
        grain: 0.005,
        glowIntensity: 0.13,
        lightX: 0.89,
        lightY: 0.46,
        lightCore: 0.14,
        lightHalo: 0.2,
        lightFollow: 0.63,
        vignette: 0.38,
        bloomThreshold: 0.61,
        bloomRange: 0.18,
        bloomStrength: 0.4,
        fps: 30,
        dprCap: 1.5,
      },
      options
    );

    const gl = canvas.getContext("webgl2", {
      alpha: true,
      premultipliedAlpha: false,
      powerPreference: "low-power",
      antialias: false,
    });
    // 没有 WebGL2 就到此为止：canvas 保持透明，底下还有 CSS 渐变兜底
    if (!gl) return;

    const flowProgram = buildProgram(gl, FLUID_VERT, FLUID_FLOW_FRAG);
    const drawProgram = buildProgram(gl, FLUID_VERT, FLUID_DRAW_FRAG);
    if (!flowProgram || !drawProgram) return;

    const quad = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, quad);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);

    function bindQuad(program) {
      const loc = gl.getAttribLocation(program, "a_position");
      gl.bindBuffer(gl.ARRAY_BUFFER, quad);
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    }

    function uniform(program, name) {
      return gl.getUniformLocation(program, name);
    }

    const flowU = {
      prev: uniform(flowProgram, "u_prev"),
      pointer: uniform(flowProgram, "u_pointer"),
      velocity: uniform(flowProgram, "u_velocity"),
      radius: uniform(flowProgram, "u_radius"),
      strength: uniform(flowProgram, "u_strength"),
      decay: uniform(flowProgram, "u_decay"),
    };

    const drawU = {};
    for (const name of [
      "u_flow", "u_resolution", "u_time", "u_scale", "u_offset",
      "u_c1", "u_c2", "u_c3", "u_c4", "u_c5",
      "u_flowDistort", "u_flowSwirl", "u_grain",
      "u_glowA", "u_glowB", "u_glowC", "u_glow",
      "u_light", "u_lightCore", "u_lightHalo", "u_vignette",
      "u_bloomThreshold", "u_bloomRange", "u_bloomStrength",
    ]) {
      drawU[name] = uniform(drawProgram, name);
    }

    function toRgb(hex) {
      const value = hex.replace("#", "");
      return [
        parseInt(value.slice(0, 2), 16) / 255,
        parseInt(value.slice(2, 4), 16) / 255,
        parseInt(value.slice(4, 6), 16) / 255,
      ];
    }

    // 五色调色板，不足的用最后一个补
    const palette = [];
    for (let i = 0; i < 5; i++) {
      palette.push(toRgb(opt.colors[i] || opt.colors[opt.colors.length - 1] || "#000000"));
    }
    const glowA = toRgb(opt.glowColors[0] || "#ffffff");
    const glowB = toRgb(opt.glowColors[1] || opt.glowColors[0] || "#ffffff");
    const glowC = toRgb(opt.glowColors[2] || opt.glowColors[0] || "#ffffff");

    // 指针状态：一层追位置、一层追速度，都做指数平滑
    const pointer = { x: 0.5, y: 0.5, smoothX: 0.5, smoothY: 0.5, vx: 0, vy: 0 };
    let hasPointer = false;

    // 归一化到 [0,1] 并翻转 y（WebGL 的纹理原点在左下）。参考页不判定指针
    // 是否落在画布内，画布外的移动照样参与——高斯刷子在边界外本就衰减到
    // 接近 0，保留这个「不判定」是为了指针停在英雄区上下缘时刷子还有半枚。
    function trackPointer(event) {
      const rect = canvas.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) return;

      pointer.x = (event.clientX - rect.left) / rect.width;
      pointer.y = 1 - (event.clientY - rect.top) / rect.height;
      hasPointer = true;
    }

    // 触屏闸门与参考页一致。参考页另外把 Windows 整个排除在外（那边只有
    // mac / Linux 划得出波纹），那是它自己的取舍，我们的受众主要在 Windows
    // 上，这条不跟。
    const coarsePointer = window.matchMedia("(hover: none), (pointer: coarse)").matches;
    const pointerEnabled = !coarsePointer && !reduceMotion.matches;

    if (pointerEnabled) {
      window.addEventListener("mousemove", trackPointer, { passive: true });
    }
    let swap = false;
    let targets = null;
    let flowWidth = 0;
    let flowHeight = 0;
    let canvasWidth = 0;
    let canvasHeight = 0;
    let raf = 0;
    let running = false;
    let visible = true;
    let resizeTimer = 0;
    let startedAt = performance.now();
    let frameStamp = 0;

    const frameBudget = 1000 / opt.fps;

    function dpr() {
      return Math.min(window.devicePixelRatio || 1, opt.dprCap);
    }

    function allocate() {
      const ratio = dpr();
      const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
      const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
      // 尺寸没变就什么都不做：重建 ping-pong 会清掉正在画的痕迹
      if (targets && width === canvasWidth && height === canvasHeight) return;

      canvasWidth = width;
      canvasHeight = height;
      canvas.width = canvasWidth;
      canvas.height = canvasHeight;

      flowWidth = Math.max(1, Math.round(canvasWidth / opt.flowScale));
      flowHeight = Math.max(1, Math.round(canvasHeight / opt.flowScale));
      targets = [createTarget(gl, flowWidth, flowHeight), createTarget(gl, flowWidth, flowHeight)];
      swap = false;
    }

    function render(time) {
      if (!targets) return;

      const config = opt;
      pointer.smoothX += (pointer.x - pointer.smoothX) * config.mouseSmoothing;
      pointer.smoothY += (pointer.y - pointer.smoothY) * config.mouseSmoothing;
      pointer.vx += ((pointer.x - pointer.smoothX) * 0.5 - pointer.vx) * config.mouseVelocity;
      pointer.vy += ((pointer.y - pointer.smoothY) * 0.5 - pointer.vy) * config.mouseVelocity;

      const elapsed = (time - startedAt) * 0.001 * (config.speed / 100);

      // 第一遍：在离屏纹理上盖一笔
      const previous = targets[swap ? 0 : 1];
      const current = targets[swap ? 1 : 0];
      swap = !swap;

      gl.bindFramebuffer(gl.FRAMEBUFFER, current.framebuffer);
      gl.viewport(0, 0, flowWidth, flowHeight);
      gl.useProgram(flowProgram);
      bindQuad(flowProgram);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, previous.texture);
      gl.uniform1i(flowU.prev, 0);
      gl.uniform2f(flowU.pointer, pointer.smoothX, pointer.smoothY);
      gl.uniform2f(flowU.velocity, pointer.vx, pointer.vy);
      gl.uniform1f(flowU.radius, config.mouseRadius);
      // 指针还没进过画布时强度给 0。参考页在这里直接按满强度盖章，指针的
      // 初始值又是画布中心，于是页面一载入中心就有一块常驻光斑——那个更像
      // 实现漏出来的痕迹，不跟。
      gl.uniform1f(
        flowU.strength,
        pointerEnabled && hasPointer ? config.mouseStrength : 0
      );
      gl.uniform1f(flowU.decay, config.decay);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);

      // 第二遍：全分辨率画出流体
      gl.viewport(0, 0, canvasWidth, canvasHeight);
      gl.useProgram(drawProgram);
      bindQuad(drawProgram);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, current.texture);
      gl.uniform1i(drawU.u_flow, 0);
      gl.uniform2f(drawU.u_resolution, canvasWidth, canvasHeight);
      gl.uniform1f(drawU.u_time, elapsed);
      gl.uniform1f(drawU.u_scale, config.scale);
      gl.uniform2f(drawU.u_offset, config.offsetX / 100, config.offsetY / 100);
      gl.uniform3f(drawU.u_c1, palette[0][0], palette[0][1], palette[0][2]);
      gl.uniform3f(drawU.u_c2, palette[1][0], palette[1][1], palette[1][2]);
      gl.uniform3f(drawU.u_c3, palette[2][0], palette[2][1], palette[2][2]);
      gl.uniform3f(drawU.u_c4, palette[3][0], palette[3][1], palette[3][2]);
      gl.uniform3f(drawU.u_c5, palette[4][0], palette[4][1], palette[4][2]);
      gl.uniform1f(drawU.u_flowDistort, config.distortBoost);
      gl.uniform1f(drawU.u_flowSwirl, config.swirlBoost);
      gl.uniform1f(drawU.u_grain, config.grain);
      gl.uniform3f(drawU.u_glowA, glowA[0], glowA[1], glowA[2]);
      gl.uniform3f(drawU.u_glowB, glowB[0], glowB[1], glowB[2]);
      gl.uniform3f(drawU.u_glowC, glowC[0], glowC[1], glowC[2]);
      gl.uniform1f(drawU.u_glow, config.glowIntensity);

      // 光源横向跟着指针走，纵向固定在 lightY
      const follow = pointerEnabled && hasPointer ? config.lightFollow : 0;
      gl.uniform2f(
        drawU.u_light,
        config.lightX + (pointer.smoothX - config.lightX) * follow,
        config.lightY
      );
      gl.uniform1f(drawU.u_lightCore, coarsePointer ? 0 : config.lightCore);
      gl.uniform1f(drawU.u_lightHalo, coarsePointer ? 0 : config.lightHalo);
      gl.uniform1f(drawU.u_vignette, config.vignette);
      gl.uniform1f(drawU.u_bloomThreshold, config.bloomThreshold);
      gl.uniform1f(drawU.u_bloomRange, config.bloomRange);
      gl.uniform1f(drawU.u_bloomStrength, config.bloomStrength);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }

    function loop(time) {
      // 不可见时不再排下一帧，交回 sync() 决定何时重启
      if (!visible || document.hidden) {
        running = false;
        raf = 0;
        return;
      }
      raf = requestAnimationFrame(loop);
      // 对齐到固定帧长的网格上，掉帧也不会让节奏漂移
      if (time - frameStamp < frameBudget) return;
      frameStamp = time - ((time - frameStamp) % frameBudget);
      render(time);
    }

    function start() {
      if (running || reduceMotion.matches) return;
      running = true;
      raf = requestAnimationFrame(loop);
    }

    function stop() {
      running = false;
      cancelAnimationFrame(raf);
      raf = 0;
    }

    function sync() {
      if (visible && !document.hidden && !reduceMotion.matches) start();
      else stop();
    }

    canvas.addEventListener("webglcontextlost", (event) => {
      event.preventDefault();
      stop();
    });
    canvas.addEventListener("webglcontextrestored", () => {
      allocate();
      sync();
    });

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(
        (entries) => {
          visible = entries.some((entry) => entry.isIntersecting);
          sync();
        },
        { threshold: 0 }
      ).observe(canvas);
    }

    document.addEventListener("visibilitychange", sync);

    if (typeof reduceMotion.addEventListener === "function") {
      reduceMotion.addEventListener("change", () => {
        sync();
        if (reduceMotion.matches) render(performance.now());
      });
    }

    // 尺寸变化后重建缓冲。用 ResizeObserver 盯画布本身而不是只听 window 的
    // resize：布局导致的尺寸变化（比如文案换行把英雄区撑高）不会触发 window
    // 的 resize，但会改动画布的盒子。
    function reallocate() {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        stop();
        allocate();
        render(performance.now());
        sync();
      }, 160);
    }

    if ("ResizeObserver" in window) {
      new ResizeObserver(reallocate).observe(canvas);
    }
    window.addEventListener("resize", reallocate);
    window.addEventListener("orientationchange", reallocate);

    startedAt = performance.now();
    allocate();
    // 先画一帧静态图：关闭动画或拿不到渲染帧时，背景也不是空的
    render(startedAt);
    sync();
  }

  /* ==========================================================
     点阵网格
     参考页的第二层背景：90px 间距的正交点阵，连线两端各缩进一截，所以
     看起来是一截截刻度而不是完整的方格。光标 140px 内的节点被推开，靠
     弹簧回位、阻尼收敛；光标附近的点同时变大变亮。速度收敛到阈值以下就
     停止排帧，由 mousemove 与滚动唤醒——静止时不占任何 CPU。
     ========================================================== */
  function createDotGrid(canvas, options) {
    if (!canvas) return;

    const opt = Object.assign(
      {
        spacing: 90,
        // 排斥力 = (1 - d / 半径) * 力度上限 * 系数，方向沿「节点 → 光标」向外
        repelRadius: 140,
        repelForce: 30,
        repelScale: 0.1,
        // 回位弹簧与阻尼
        spring: 0.05,
        damping: 0.85,
        // 所有节点速度都低于它就不再排下一帧
        settleSpeed: 0.01,
        lineColor: "rgba(255, 255, 255,",
        dotColor: "rgba(255, 255, 255,",
        lineOpacity: 0.08,
        dotOpacity: 0.16,
        lineWidth: 0.5,
        lineInset: 10,
        minSegment: 20,
        dotRadius: 1.8,
        dotGrow: 2,
        dotAlphaGrow: 0.4,
        fps: 30,
        dprCap: 2,
        // 静态版：不接收鼠标，只在进入视口时画一帧
        isStatic: false,
      },
      options
    );

    // 参考页在触屏上直接把这块画布丢掉
    if (window.matchMedia("(hover: none), (pointer: coarse)").matches) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // 静态版与 reduced-motion 都不接管鼠标
    const interactive = !opt.isStatic && !reduceMotion.matches;
    const frameBudget = 1000 / opt.fps;

    let nodes = [];
    let cols = 0;
    let rows = 0;
    let width = 0;
    let height = 0;
    let raf = 0;
    let visible = true;
    let settled = true;
    let stamp = 0;
    let resizeTimer = 0;
    const mouse = { x: NaN, y: NaN };

    function build() {
      cols = Math.ceil(width / opt.spacing) + 1;
      rows = Math.ceil(height / opt.spacing) + 1;
      // 多出来的余量平分到两侧，点阵整体居中
      const originX = (width - (cols - 1) * opt.spacing) / 2;
      const originY = (height - (rows - 1) * opt.spacing) / 2;
      nodes = [];
      for (let row = 0; row < rows; row++) {
        for (let col = 0; col < cols; col++) {
          const x = originX + col * opt.spacing;
          const y = originY + row * opt.spacing;
          nodes.push({ restX: x, restY: y, x, y, vx: 0, vy: 0 });
        }
      }
    }

    function segment(from, to) {
      const dx = to.x - from.x;
      const dy = to.y - from.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < opt.minSegment) return;
      const ux = dx / dist;
      const uy = dy / dist;
      ctx.beginPath();
      ctx.moveTo(from.x + ux * opt.lineInset, from.y + uy * opt.lineInset);
      ctx.lineTo(to.x - ux * opt.lineInset, to.y - uy * opt.lineInset);
      ctx.stroke();
    }

    /* 推进一帧并画出，返回本帧最大节点速度（调用方据此判断是否停帧） */
    function step() {
      ctx.clearRect(0, 0, width, height);

      const mx = mouse.x;
      const my = mouse.y;
      const hasMouse = !Number.isNaN(mx) && !Number.isNaN(my);
      let maxSpeed = 0;

      for (const node of nodes) {
        if (hasMouse) {
          const dx = node.x - mx;
          const dy = node.y - my;
          const dist = Math.sqrt(dx * dx + dy * dy);
          // 落在光标正下方时方向无意义，跳过
          if (dist < opt.repelRadius && dist > 0.1) {
            const force = (1 - dist / opt.repelRadius) * opt.repelForce * opt.repelScale;
            node.vx += (dx / dist) * force;
            node.vy += (dy / dist) * force;
          }
        }

        node.vx += (node.restX - node.x) * opt.spring;
        node.vy += (node.restY - node.y) * opt.spring;
        node.vx *= opt.damping;
        node.vy *= opt.damping;
        node.x += node.vx;
        node.y += node.vy;

        const speed = Math.abs(node.vx) + Math.abs(node.vy);
        if (speed > maxSpeed) maxSpeed = speed;
      }

      ctx.lineWidth = opt.lineWidth;
      ctx.strokeStyle = opt.lineColor + " " + opt.lineOpacity + ")";
      for (let row = 0; row < rows; row++) {
        for (let col = 0; col < cols - 1; col++) {
          segment(nodes[row * cols + col], nodes[row * cols + col + 1]);
        }
      }
      for (let col = 0; col < cols; col++) {
        for (let row = 0; row < rows - 1; row++) {
          segment(nodes[row * cols + col], nodes[(row + 1) * cols + col]);
        }
      }

      ctx.fillStyle = opt.dotColor + " " + opt.dotOpacity + ")";
      for (const node of nodes) {
        let radius = opt.dotRadius;
        let alpha = opt.dotOpacity;
        if (hasMouse) {
          const falloff = Math.max(
            0,
            1 - Math.hypot(node.x - mx, node.y - my) / opt.repelRadius
          );
          radius += opt.dotGrow * falloff;
          alpha += opt.dotAlphaGrow * falloff;
        }
        ctx.globalAlpha = alpha;
        const side = radius * 2;
        ctx.fillRect(node.x - radius, node.y - radius, side, side);
      }
      ctx.globalAlpha = 1;

      return maxSpeed;
    }

    function loop(time) {
      // 不可见就不再排帧，交回 start() 决定何时重启
      if (!visible) {
        raf = 0;
        return;
      }
      raf = requestAnimationFrame(loop);
      // 对齐到固定帧长的网格上，掉帧也不会让节奏漂移
      if (time - stamp < frameBudget) return;
      stamp = time - ((time - stamp) % frameBudget);

      if (step() < opt.settleSpeed) {
        settled = true;
        cancelAnimationFrame(raf);
        raf = 0;
      }
    }

    function start() {
      if (raf) return;
      settled = false;
      raf = requestAnimationFrame(loop);
    }

    function stop() {
      cancelAnimationFrame(raf);
      raf = 0;
    }

    function onPointerMove(event) {
      const rect = canvas.getBoundingClientRect();
      mouse.x = event.clientX - rect.left;
      mouse.y = event.clientY - rect.top;
      // 已经收敛时才需要唤醒，否则本来就在跑
      if (settled) start();
    }

    function resizeNow() {
      // DPR 每次都重新读：页面刚起来时它可能还没稳定，抓一次就定死会让整块
      // 网格一直按错的比例作图
      const ratio = Math.min(window.devicePixelRatio || 1, opt.dprCap);
      width = canvas.clientWidth;
      height = canvas.clientHeight;
      canvas.width = Math.max(1, Math.round(width * ratio));
      canvas.height = Math.max(1, Math.round(height * ratio));
      // 作图一律按 CSS 像素，DPR 交给变换矩阵
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      build();
    }

    function onResize() {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        stop();
        resizeNow();
        start();
      }, 150);
    }

    if (interactive) {
      window.addEventListener("mousemove", onPointerMove, { passive: true });
    }

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(
        (entries) => {
          visible = entries.some((entry) => entry.isIntersecting);
          if (visible) start();
          else stop();
        },
        { threshold: 0 }
      ).observe(canvas);
    }

    // 收敛停帧之后窗口还可能被拖动。参考页只在帧循环里查尺寸，停帧后就会
    // 留下一块错位的网格，直到鼠标再次移动才恢复；这里改成盯画布本身。
    if ("ResizeObserver" in window) {
      new ResizeObserver(onResize).observe(canvas);
    } else {
      window.addEventListener("resize", onResize);
    }

    resizeNow();
    start();
  }

  /* 英雄区：主视觉。流体打底，上面再叠一层跟着鼠标走的点阵网格 */
  createFluid(document.getElementById("hero-canvas"), {
    fps: 30,
    flowScale: 4,
  });

  createDotGrid(document.getElementById("hero-grid"), {
    lineOpacity: 0.08,
    dotOpacity: 0.16,
  });

  /* 收尾区：同一个场，更慢更暗，只做背景 */
  createFluid(document.getElementById("closing-canvas"), {
    fps: 24,
    flowScale: 6,
    dprCap: 1.25,
    speed: 18,
    glowIntensity: 0.11,
    vignette: 0.34,
    colors: ["#010304", "#0c2f3c", "#104456", "#e6c6ab", "#010304"],
  });

  /* ---------- 生成结果面板的页签 ---------- */
  document.querySelectorAll(".terminal__tabs").forEach((tablist) => {
    const tabs = Array.from(tablist.querySelectorAll('[role="tab"]'));
    const terminal = tablist.closest(".terminal");
    if (!terminal || tabs.length === 0) return;

    const panes = Array.from(terminal.querySelectorAll(".terminal__pane"));

    function select(tab) {
      const targetId = tab.getAttribute("aria-controls");
      tabs.forEach((item) => {
        item.setAttribute("aria-selected", String(item === tab));
        item.tabIndex = item === tab ? 0 : -1;
      });
      panes.forEach((pane) => {
        pane.dataset.active = String(pane.id === targetId);
      });
    }

    tabs.forEach((tab, index) => {
      tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1;
      tab.addEventListener("click", () => select(tab));
      tab.addEventListener("keydown", (event) => {
        const offset = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
        if (offset === 0) return;
        event.preventDefault();
        const next = tabs[(index + offset + tabs.length) % tabs.length];
        select(next);
        next.focus();
      });
    });
  });

  /* ---------- 复制按钮 ---------- */
  function setCopyLabel(button, text) {
    const span = button.querySelector("span");
    if (span) {
      span.textContent = text;
      return;
    }
    // 没有 span 时只改末尾的文本节点，保留前面图标
    const textNode = Array.from(button.childNodes)
      .reverse()
      .find((node) => node.nodeType === Node.TEXT_NODE && node.textContent.trim());
    if (textNode) textNode.textContent = text;
  }

  async function writeClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (error) {
        /* 继续走 execCommand 回退 */
      }
    }
    try {
      const scratch = document.createElement("textarea");
      scratch.value = text;
      scratch.setAttribute("readonly", "");
      scratch.style.position = "fixed";
      scratch.style.top = "-1000px";
      document.body.appendChild(scratch);
      scratch.select();
      const ok = document.execCommand("copy");
      scratch.remove();
      return ok;
    } catch (error) {
      return false;
    }
  }

  document.querySelectorAll("[data-copy], [data-copy-pane]").forEach((button) => {
    button.addEventListener("click", async () => {
      let text = button.dataset.copy;

      if (button.hasAttribute("data-copy-pane")) {
        const terminal = button.closest(".terminal");
        const pane =
          terminal && terminal.querySelector('.terminal__pane[data-active="true"]');
        text = pane ? pane.textContent : "";
      }

      if (!text) return;

      const ok = await writeClipboard(text);
      setCopyLabel(button, ok ? button.dataset.copyLabel || "已复制" : "复制失败");

      clearTimeout(button.copyResetTimer);
      button.copyResetTimer = setTimeout(() => setCopyLabel(button, "复制"), 1600);
    });
  });

  /* ---------- 滚动揭示 ---------- */
  const reveals = Array.from(document.querySelectorAll(".reveal, .closing__grid"));
  const revealAll = () =>
    reveals.forEach((element) => element.classList.add("is-visible"));

  if (reduceMotion.matches || !("IntersectionObserver" in window)) {
    revealAll();
  } else {
    let fired = false;
    const observer = new IntersectionObserver(
      (entries) => {
        fired = true;
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.06 }
    );
    reveals.forEach((element) => observer.observe(element));

    // 兜底：观察器一次都没回调时（渲染被挂起等极端情况）直接放行全部内容
    setTimeout(() => {
      if (!fired) revealAll();
    }, 2500);
  }
})();
