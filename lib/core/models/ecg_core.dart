// El motor del ECG del Explorador de 12 derivaciones. Puerto de la web: src/lib/electros/leads.ts y
// ecgCore.ts, línea a línea (test/ecg_test.dart compara la síntesis de cada patrón con la de la web).
//
// Dos etapas:
//  1) generador de RITMO → cuándo ocurre cada latido / onda P / actividad auricular;
//  2) estampado de MORFOLOGÍA por derivación → 12 buffers de voltaje (mV), con la tabla de
//     derivaciones: las de miembros salen de proyectar el eje eléctrico, las precordiales de una tabla
//     normal que los «mods» (BRD, BRI, HVI, SCACEST…) modifican.
//
// Lo que en JS es `x || 0.2` (0 cuenta como falso) se respeta tal cual: cambia el dibujo. Los buffers
// son Float32List como los Float32Array de la web, para redondear igual.
//
// Aquí no hay Flutter: es lo que se prueba sin pantallas.

import 'dart:math' as math;
import 'dart:typed_data';

const int fsEcg = 500; // Hz
const int durEcg = 10; // s (tira de ritmo estándar)
const int _n = fsEcg * durEcg;

const List<String> ordenDerivaciones = ['I', 'II', 'III', 'aVR', 'aVL', 'aVF', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6'];

/* ════════════════════════════════════════════════════════════════════════
   Tabla de derivaciones (leads.ts)
═══════════════════════════════════════════════════════════════════════════ */

/// Morfología de una derivación. Amplitudes en mV.
class OndaEcg {
  double p, q, r, s, rp, t, j, u, prDep, delta, notch, tSym;

  OndaEcg({
    this.p = 0,
    this.q = 0,
    this.r = 0,
    this.s = 0,
    this.rp = 0,
    this.t = 0,
    this.j = 0,
    this.u = 0,
    this.prDep = 0,
    this.delta = 0,
    this.notch = 0,
    this.tSym = 0,
  });

  OndaEcg copia() => OndaEcg(
        p: p, q: q, r: r, s: s, rp: rp, t: t, j: j, u: u, prDep: prDep, delta: delta, notch: notch, tSym: tSym,
      );
}

typedef TablaDerivaciones = Map<String, OndaEcg>;

const Map<String, double> _angulosMiembros = {'I': 0, 'II': 60, 'III': 120, 'aVR': -150, 'aVL': -30, 'aVF': 90};
const double _deg = math.pi / 180;
double _proj(double angulo, double eje) => math.cos((angulo - eje) * _deg);

/// `Math.sign` de JS (0 → 0).
double _sign(double x) => x > 0 ? 1 : (x < 0 ? -1 : 0);

/// `x || alternativa` de JS para números: 0 (y NaN) cuentan como falsos.
double _o(double x, double alternativa) => (x == 0 || x.isNaN) ? alternativa : x;

/// La tabla base de 12 derivaciones para un patrón (antes de los mods).
TablaDerivaciones baseDerivaciones({
  double qrsMag = 1.2,
  double qrsAxis = 60,
  double pMag = 0.15,
  double pAxis = 55,
  double tMag = 0.35,
  double tAxis = 45,
}) {
  final out = <String, OndaEcg>{};
  _angulosMiembros.forEach((nombre, a) {
    final net = qrsMag * _proj(a, qrsAxis); // deflexión neta del QRS
    out[nombre] = OndaEcg(
      p: pMag * _proj(a, pAxis),
      // pequeña q septal solo donde la R es claramente dominante
      q: net > 0.4 ? -0.05 : 0,
      r: net > 0 ? net + 0.06 : 0.06,
      s: net < 0 ? net - 0.05 : -0.09,
      t: tMag * _proj(a, tAxis),
    );
  });
  // Precordiales normales: V1 rS → transición en V3-V4 → V5-V6 qR dominante.
  out['V1'] = OndaEcg(p: 0.05, r: 0.2, s: -0.95, t: -0.05);
  out['V2'] = OndaEcg(p: 0.08, r: 0.4, s: -1.35, t: 0.35);
  out['V3'] = OndaEcg(p: 0.08, r: 0.7, s: -0.95, t: 0.45);
  out['V4'] = OndaEcg(p: 0.08, q: -0.05, r: 1.35, s: -0.5, t: 0.5);
  out['V5'] = OndaEcg(p: 0.08, q: -0.08, r: 1.3, s: -0.25, t: 0.38);
  out['V6'] = OndaEcg(p: 0.06, q: -0.06, r: 1.0, s: -0.12, t: 0.28);
  return out;
}

void _each(TablaDerivaciones l, List<String> nombres, void Function(OndaEcg w) fn) {
  for (final n in nombres) {
    final w = l[n];
    if (w != null) fn(w);
  }
}

void _all(TablaDerivaciones l, void Function(OndaEcg w, String n) fn) => l.forEach((n, w) => fn(w, n));

/// Territorios coronarios para SCACEST (elevación) y sus recíprocas (descenso).
const Map<String, ({List<String> up, List<String> recip})> _territorios = {
  'anterior': (up: ['V1', 'V2', 'V3', 'V4'], recip: ['II', 'III', 'aVF']),
  'anteroseptal': (up: ['V1', 'V2', 'V3'], recip: ['II', 'III', 'aVF']),
  'lateral': (up: ['I', 'aVL', 'V5', 'V6'], recip: ['III', 'aVF']),
  'inferior': (up: ['II', 'III', 'aVF'], recip: ['I', 'aVL']),
  'extenso': (up: ['I', 'aVL', 'V1', 'V2', 'V3', 'V4', 'V5', 'V6'], recip: ['III']),
};

/// Las transformaciones patológicas: cada una recibe la tabla y la muta.
final Map<String, void Function(TablaDerivaciones l, String? arg)> modsEcg = {
  // Hipertrofia ventricular izquierda + sobrecarga
  'lvh': (l, _) {
    _each(l, ['V1', 'V2'], (w) => w.s *= 1.7);
    _each(l, ['V5', 'V6'], (w) => w.r *= 1.6);
    _each(l, ['I', 'aVL'], (w) => w.r *= 1.4);
    _each(l, ['I', 'aVL', 'V5', 'V6'], (w) {
      w.j = -0.1;
      w.t = -w.t.abs() * 0.9;
    });
  },
  // Hipertrofia ventricular derecha
  'rvh': (l, _) {
    l['V1']!
      ..r = 1.1
      ..s = -0.2
      ..t = -0.25;
    l['V2']!
      ..r = 0.9
      ..s = -0.5
      ..t = -0.2;
    _each(l, ['V5', 'V6'], (w) {
      w.s *= 1.6;
      w.r *= 0.8;
    });
  },
  // Bloqueo de rama derecha (el QRS ancho lo pone el patrón)
  'rbbb': (l, _) {
    l['V1']!
      ..r = 0.25
      ..s = -0.15
      ..rp = 0.9;
    l['V2']!
      ..r = 0.3
      ..s = -0.3
      ..rp = 0.6;
    _each(l, ['I', 'aVL', 'V5', 'V6'], (w) => w.s = math.min(w.s, -0.35));
    _each(l, ['V1', 'V2', 'V3'], (w) => w.t = -_o(w.t, 0.2).abs());
  },
  // Bloqueo de rama izquierda
  'lbbb': (l, _) {
    _each(l, ['V1', 'V2', 'V3'], (w) {
      w.r = 0.05;
      w.s = -1.5;
      w.rp = 0;
      w.q = 0;
    });
    _each(l, ['I', 'aVL', 'V5', 'V6'], (w) {
      w.q = 0;
      w.r = math.max(w.r, 1.4);
      w.s = -0.05;
      w.notch = 1;
    });
    // discordancia apropiada: ST/T opuestos a la deflexión dominante
    _all(l, (w, _) {
      final dom = w.r + w.rp + w.s;
      if (dom > 0.3) {
        w.j = -0.1;
        w.t = -_o(w.t, 0.3).abs() - 0.1;
      } else if (dom < -0.3) {
        w.j = 0.12;
        w.t = w.t.abs() + 0.2;
      }
    });
  },
  // SCACEST (IAM con elevación del ST) por territorio
  'stemi': (l, arg) {
    final t = _territorios[arg ?? 'anterior'] ?? _territorios['anterior']!;
    _each(l, t.up, (w) {
      w.j = 0.32;
      w.t = _o(w.t, 0.3).abs() + 0.35;
      w.q = math.min(w.q, -0.25);
      w.r *= 0.55;
    });
    _each(l, t.recip, (w) {
      w.j = -0.14;
      w.t = -_o(w.t, 0.2).abs();
    });
  },
  // SCASEST / isquemia subendocárdica
  'ischemia': (l, arg) {
    final up = (_territorios[arg ?? 'lateral'] ?? _territorios['lateral']!).up;
    _each(l, up, (w) {
      w.j = -0.18;
      w.t = -0.35;
      w.tSym = 1;
    });
  },
  // Wellens: T bifásicas/negativas profundas V2-V4
  'wellens': (l, _) {
    _each(l, ['V2', 'V3', 'V4'], (w) {
      w.t = -0.55;
      w.tSym = 1;
      w.j = 0.02;
    });
  },
  // Pericarditis aguda: elevación cóncava difusa + descenso del PR
  'pericarditis': (l, _) {
    _all(l, (w, n) {
      if (n == 'aVR' || n == 'V1') {
        w.j = -0.05;
        w.prDep = 0.05;
      } else {
        w.j = 0.12;
        w.prDep = -0.06;
      }
    });
  },
  // Hiperpotasemia: T picudas simétricas, P aplanada
  'hyperk': (l, _) {
    _all(l, (w, _) {
      if (w.t.abs() > 0.02) {
        w.t = _sign(_o(w.t, 1)) * (w.t.abs() + 0.5);
        w.tSym = 1;
      }
      w.p *= 0.2;
    });
  },
  // Hipopotasemia: T aplanada, onda U prominente, ST descendido
  'hypok': (l, _) {
    _all(l, (w, _) {
      w.t *= 0.4;
      w.u = 0.22 * _sign(_o(w.r, 1));
      w.j = -0.06;
    });
  },
  // Brugada tipo 1
  'brugada': (l, _) {
    _each(l, ['V1', 'V2'], (w) {
      w.r = 0.2;
      w.rp = 0.35;
      w.j = 0.28;
      w.t = -0.3;
      w.tSym = 1;
    });
  },
  // WPW: onda delta difusa (el PR corto lo pone el patrón)
  'wpw': (l, _) => _all(l, (w, _) => w.delta = 0.25 * _sign(w.r + 0.01)),
  // Bajo voltaje (derrame/taponamiento)
  'lowvoltage': (l, _) {
    _all(l, (w, _) {
      w.q *= 0.4;
      w.r *= 0.4;
      w.s *= 0.4;
      w.t *= 0.4;
    });
  },
  // Crecimiento auricular
  'pmitrale': (l, _) => _each(l, ['II'], (w) => w.p = 0.16),
  'ppulmonale': (l, _) => _each(l, ['II', 'III', 'aVF'], (w) => w.p = 0.3),
  // Impregnación digitálica: cazoleta lateral
  'digoxin': (l, _) {
    _each(l, ['V5', 'V6', 'I'], (w) {
      w.j = -0.12;
      w.t = -0.1;
    });
  },
};

/// Aplica una lista de mods ('stemi:anterior', 'rbbb', …) sobre la tabla.
TablaDerivaciones aplicarMods(TablaDerivaciones l, List<String> mods) {
  for (final m in mods) {
    final partes = m.split(':');
    modsEcg[partes[0]]?.call(l, partes.length > 1 ? partes[1] : null);
  }
  return l;
}

/* ════════════════════════════════════════════════════════════════════════
   Patrones (los datos están en ecg_patrones.dart, generado de la web)
═══════════════════════════════════════════════════════════════════════════ */

/// Parámetros morfológicos de un patrón (los `morph` de patterns.ts).
class MorfologiaEcg {
  final double? qrsWidth, tWidth, qtScale, pWidth, pNotch, pPeak, pr;
  final double? qrsMag, qrsAxis, pMag, pAxis, tMag, tAxis;
  final List<String> mods;

  const MorfologiaEcg({
    this.qrsWidth,
    this.tWidth,
    this.qtScale,
    this.pWidth,
    this.pNotch,
    this.pPeak,
    this.pr,
    this.qrsMag,
    this.qrsAxis,
    this.pMag,
    this.pAxis,
    this.tMag,
    this.tAxis,
    this.mods = const [],
  });
}

enum GravedadEcg { normal, warn, crit }

class IntervaloEcg {
  final String clave;
  final String valor;
  const IntervaloEcg(this.clave, this.valor);
}

class PatronEcg {
  final String id;
  final String nombre;
  final String sigla;
  final String categoria;
  final GravedadEcg gravedad;
  final int fc;
  final String ritmo;
  final MorfologiaEcg morfologia;
  final Map<String, double> parametrosRitmo;
  final List<IntervaloEcg> intervalos;
  final String resumen;
  final List<String> claves;
  final String perla;

  /// Nombre, sigla y sinónimos: lo que acepta el buscador del modo examen.
  final List<String> busqueda;

  const PatronEcg({
    required this.id,
    required this.nombre,
    required this.sigla,
    required this.categoria,
    required this.gravedad,
    required this.fc,
    required this.ritmo,
    required this.morfologia,
    this.parametrosRitmo = const {},
    required this.intervalos,
    required this.resumen,
    required this.claves,
    required this.perla,
    required this.busqueda,
  });
}

/* ════════════════════════════════════════════════════════════════════════
   Síntesis (ecgCore.ts)
═══════════════════════════════════════════════════════════════════════════ */

class SintesisEcg {
  final Map<String, Float32List> derivaciones;

  /// Tiempos (s) de cada R, para sincronizar el latido del monitor.
  final List<double> latidos;
  final int fs;
  final int dur;
  final int fc;

  const SintesisEcg({required this.derivaciones, required this.latidos, required this.fs, required this.dur, required this.fc});
}

class _Timing {
  final double qrsWidth, tWidth, qtScale, pWidth, pNotch, pPeak;
  const _Timing({
    required this.qrsWidth,
    required this.tWidth,
    required this.qtScale,
    required this.pWidth,
    required this.pNotch,
    required this.pPeak,
  });

  _Timing conQrs(double qrs) =>
      _Timing(qrsWidth: qrs, tWidth: tWidth, qtScale: qtScale, pWidth: pWidth, pNotch: pNotch, pPeak: pPeak);
}

enum _TipoLatido { sinus, pvc, escape, torsade }

class _Latido {
  final double t;
  final _TipoLatido tipo;
  const _Latido(this.t, this.tipo);
}

class _Ritmo {
  final List<_Latido> latidos;
  final List<double> ondasP;
  final void Function(Float32List buf, String nombre)? basal;
  final bool polimorfico;
  final String? caos;
  const _Ritmo(this.latidos, this.ondasP, {this.basal, this.polimorfico = false, this.caos});
}

double _gauss(double t, double c, double amp, double w) => amp * math.exp(-0.5 * math.pow((t - c) / w, 2));

/// Meseta plana (súper-gaussiana) para segmentos ST / PR.
double _plateau(double t, double c, double amp, double w) => amp * math.exp(-math.pow((t - c) / w, 4));

/// El generador pseudoaleatorio de la web (congruencial lineal de 32 bits): mismas semillas, mismos
/// números, así la FA y la FV tienen la misma forma en la app que en la web.
double Function() rngEcg(int semilla) {
  var s = semilla & 0xFFFFFFFF;
  return () {
    s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
    return s / 4294967296;
  };
}

/// Estampado de un latido en UNA derivación.
void _estamparLatido(Float32List buf, double tR, OndaEcg w, _Timing tm) {
  final qw = tm.qrsWidth;
  final qt = tm.qtScale;
  final tw = tm.tWidth;
  final i0 = math.max(0, ((tR - 0.12 * qw) * fsEcg).floor());
  final i1 = math.min(_n, ((tR + 0.52 * qt) * fsEcg).ceil());
  final tPeak = (0.3 + 0.03 * qw) * qt; // posición de la T
  for (var i = i0; i < i1; i++) {
    final tau = i / fsEcg - tR;
    double y = 0;
    // Onda delta (preexcitación): empastamiento previo a la R
    if (w.delta != 0) y += _gauss(tau, -0.05 * qw, w.delta, 0.03 * qw);
    // Segmento PR (desnivel, p. ej. pericarditis)
    if (w.prDep != 0) y += _plateau(tau, -0.07, w.prDep, 0.035);
    // Q — R — S
    y += _gauss(tau, -0.024 * qw, w.q, 0.011 * qw);
    y += _gauss(tau, 0, w.r, 0.013 * qw);
    if (w.notch != 0) y += _gauss(tau, 0.016 * qw, -w.r.abs() * 0.28, 0.01 * qw);
    y += _gauss(tau, 0.03 * qw, w.s, 0.015 * qw);
    // R' (orejas de conejo del BRD)
    if (w.rp != 0) y += _gauss(tau, 0.06 * qw, w.rp, 0.017 * qw);
    // Segmento ST (nivel del punto J)
    if (w.j != 0) y += _plateau(tau, 0.115 + 0.02 * qw, w.j, 0.05);
    // Onda T (asimétrica normal; simétrica si tSym)
    final twR = 0.06 * tw;
    final twL = w.tSym != 0 ? twR : twR * 1.5;
    y += tau < tPeak ? _gauss(tau, tPeak, w.t, twL) : _gauss(tau, tPeak, w.t, twR);
    // Onda U
    if (w.u != 0) y += _gauss(tau, tPeak + 0.16 * qt, w.u, 0.05);
    buf[i] += y;
  }
}

/// Estampado de una onda P (auricular).
void _estamparP(Float32List buf, double tP, OndaEcg w, _Timing tm) {
  if (w.p == 0) return;
  final pw = 0.022 * _o(tm.pWidth, 1);
  final i0 = math.max(0, ((tP - 4 * pw) * fsEcg).floor());
  final i1 = math.min(_n, ((tP + 4 * pw) * fsEcg).ceil());
  for (var i = i0; i < i1; i++) {
    final t = i / fsEcg;
    if (tm.pNotch != 0) {
      // P mitrale: dos jorobas
      buf[i] += _gauss(t, tP - 0.02, w.p * 0.9, pw * 0.7) + _gauss(t, tP + 0.022, w.p, pw * 0.7);
    } else if (tm.pPeak != 0) {
      // P pulmonale: alta y picuda
      buf[i] += _gauss(t, tP, w.p, pw * 0.75);
    } else {
      buf[i] += _gauss(t, tP, w.p, pw);
    }
  }
}

/// Pesos de visibilidad de la actividad auricular (flutter/fibrilación se ven mejor en II/III/aVF/V1).
const Map<String, double> _pesoAuricular = {
  'I': 0.3, 'II': 1.0, 'III': 0.9, 'aVR': -0.6, 'aVL': -0.2, 'aVF': 0.9,
  'V1': 0.8, 'V2': 0.4, 'V3': 0.2, 'V4': 0.15, 'V5': 0.1, 'V6': 0.1,
};

void _basalFlutter(Float32List buf, String nombre) {
  final wgt = _pesoAuricular[nombre] ?? 0.3;
  const periodo = 1 / 5; // 300/min = 5 Hz
  for (var i = 0; i < _n; i++) {
    final ph = ((i / fsEcg) % periodo) / periodo; // diente de sierra 0..1
    buf[i] += (-0.16 * ph + 0.08) * wgt;
  }
}

void _basalFibrilacion(Float32List buf, String nombre, double Function() rand) {
  final wgt = _pesoAuricular[nombre] ?? 0.3;
  final comps = <({double f, double ph, double a})>[];
  for (var k = 0; k < 6; k++) {
    comps.add((f: 5 + rand() * 5, ph: rand() * 6.28, a: 0.5 + rand()));
  }
  for (var i = 0; i < _n; i++) {
    final t = i / fsEcg;
    double y = 0;
    for (final c in comps) {
      y += c.a * math.sin(2 * math.pi * c.f * t + c.ph);
    }
    buf[i] += (y / comps.length) * 0.06 * wgt;
  }
}

/// Generadores de ritmo: cuándo late cada QRS y dónde van las P.
_Ritmo _generarRitmo(String nombre, {required double hr, required double pr, double? pp, double? start}) {
  switch (nombre) {
    case 'noP':
      // Sin ondas P visibles (TPSV) o anchas (TV)
      final rr = 60 / hr;
      return _Ritmo([for (var t = start ?? 0.45; t < durEcg; t += rr) _Latido(t, _TipoLatido.sinus)], const []);
    case 'afib':
      final rand = rngEcg(7);
      final latidos = <_Latido>[];
      final media = 60 / hr;
      var t = 0.5;
      while (t < durEcg) {
        latidos.add(_Latido(t, _TipoLatido.sinus));
        t += media * (0.5 + rand() * 1.0);
      }
      return _Ritmo(latidos, const [], basal: (buf, n) => _basalFibrilacion(buf, n, rngEcg(7)));
    case 'aflutter':
      final rr = 60 / hr;
      return _Ritmo([for (var t = 0.6; t < durEcg; t += rr) _Latido(t, _TipoLatido.sinus)], const [],
          basal: _basalFlutter);
    case 'wenckebach':
      final paso = pp ?? 0.82;
      final latidos = <_Latido>[];
      final ondasP = <double>[];
      var n = 0;
      for (var t = 0.5; t < durEcg; t += paso, n++) {
        ondasP.add(t);
        if (n % 4 == 3) continue; // 4ª P bloqueada
        latidos.add(_Latido(t + 0.16 + (n % 4) * 0.07, _TipoLatido.sinus));
      }
      return _Ritmo(latidos, ondasP);
    case 'mobitz2':
      final paso = pp ?? 0.8;
      final latidos = <_Latido>[];
      final ondasP = <double>[];
      var n = 0;
      for (var t = 0.5; t < durEcg; t += paso, n++) {
        ondasP.add(t);
        if (n % 3 == 2) continue; // QRS caído sin previo aviso
        latidos.add(_Latido(t + pr, _TipoLatido.sinus));
      }
      return _Ritmo(latidos, ondasP);
    case 'avblock3':
      // Disociación AV: aurículas ~92/min, escape ventricular lento e independiente
      return _Ritmo(
        [for (var t = 0.7; t < durEcg; t += 60 / hr) _Latido(t, _TipoLatido.escape)],
        [for (var t = 0.4; t < durEcg; t += 60 / 92) t],
      );
    case 'bigeminy':
      final rr = 60 / hr;
      final latidos = <_Latido>[];
      final ondasP = <double>[];
      var t = 0.55;
      var i = 0;
      while (t < durEcg) {
        if (i % 2 == 0) {
          ondasP.add(t - 0.16);
          latidos.add(_Latido(t, _TipoLatido.sinus));
          t += rr * 0.6;
        } else {
          latidos.add(_Latido(t, _TipoLatido.pvc));
          t += rr * 1.4;
        }
        i++;
      }
      return _Ritmo(latidos, ondasP);
    case 'torsades':
      final rr = 60 / hr;
      return _Ritmo([for (var t = 0.4; t < durEcg; t += rr) _Latido(t, _TipoLatido.torsade)], const [],
          polimorfico: true);
    case 'vfib':
      return const _Ritmo([], [], caos: 'vfib');
    case 'asystole':
      return const _Ritmo([], [], caos: 'asystole');
    case 'regular':
    default:
      final rr = 60 / hr;
      final latidos = <_Latido>[];
      final ondasP = <double>[];
      for (var t = 0.55; t < durEcg; t += rr) {
        latidos.add(_Latido(t, _TipoLatido.sinus));
        ondasP.add(t - pr);
      }
      return _Ritmo(latidos, ondasP);
  }
}

/// Extrasístole ventricular: complejo ancho y bizarro por derivación (tipo BRI, foco VD).
TablaDerivaciones _derivacionesEv() {
  final l = {for (final n in ordenDerivaciones) n: OndaEcg()};
  for (final n in ['V1', 'V2', 'V3', 'III', 'aVF', 'aVR']) {
    l[n]!
      ..s = -1.5
      ..r = 0.15
      ..t = 0.5;
  }
  for (final n in ['I', 'aVL', 'V5', 'V6', 'II', 'V4']) {
    l[n]!
      ..r = 1.5
      ..s = -0.1
      ..t = -0.6;
  }
  return l;
}

/// Las 12 derivaciones de un patrón: 10 s a 500 Hz.
SintesisEcg sintetizar(PatronEcg patron) {
  final m = patron.morfologia;
  final tm = _Timing(
    qrsWidth: m.qrsWidth ?? 1,
    tWidth: m.tWidth ?? 1,
    qtScale: m.qtScale ?? 1,
    pWidth: m.pWidth ?? 1,
    pNotch: m.pNotch ?? 0,
    pPeak: m.pPeak ?? 0,
  );
  final pr = m.pr ?? 0.16;

  final l = baseDerivaciones(
    qrsMag: m.qrsMag ?? 1.2,
    qrsAxis: m.qrsAxis ?? 60,
    pMag: m.pMag ?? 0.15,
    pAxis: m.pAxis ?? 55,
    tMag: m.tMag ?? 0.35,
    tAxis: m.tAxis ?? 45,
  );
  aplicarMods(l, m.mods);

  // `{ hr, pr, ...pattern.rhythm }`: los parámetros del patrón pisan a hr y pr.
  final extra = patron.parametrosRitmo;
  final ritmo = _generarRitmo(
    patron.ritmo,
    hr: extra['hr'] ?? patron.fc.toDouble(),
    pr: extra['pr'] ?? pr,
    pp: extra['pp'],
    start: extra['start'],
  );

  final derivaciones = <String, Float32List>{};
  final ruido = rngEcg(42);
  for (final nombre in ordenDerivaciones) {
    final buf = Float32List(_n);
    // ruido muscular + deriva de la línea de base (realismo)
    for (var i = 0; i < _n; i++) {
      buf[i] += (ruido() - 0.5) * 0.01;
      buf[i] += math.sin(2 * math.pi * 0.22 * (i / fsEcg) + nombre.length) * 0.01;
    }
    derivaciones[nombre] = buf;
  }

  if (ritmo.caos == 'vfib') {
    for (final nombre in ordenDerivaciones) {
      final r = rngEcg(11 + nombre.length);
      final comps = <({double f, double ph, double a})>[];
      for (var k = 0; k < 7; k++) {
        comps.add((f: 3 + r() * 5, ph: r() * 6.28, a: 0.18 + r() * 0.3));
      }
      final buf = derivaciones[nombre]!;
      for (var i = 0; i < _n; i++) {
        final t = i / fsEcg;
        double y = 0;
        for (final c in comps) {
          y += c.a * math.sin(2 * math.pi * c.f * t + c.ph + math.sin(t * 1.7) * 1.5);
        }
        buf[i] = y;
      }
    }
    return SintesisEcg(derivaciones: derivaciones, latidos: const [], fs: fsEcg, dur: durEcg, fc: patron.fc);
  }
  if (ritmo.caos == 'asystole') {
    for (final nombre in ordenDerivaciones) {
      final r = rngEcg(5 + nombre.length);
      final buf = derivaciones[nombre]!;
      for (var i = 0; i < _n; i++) {
        buf[i] = (r() - 0.5) * 0.02;
      }
    }
    return SintesisEcg(derivaciones: derivaciones, latidos: const [], fs: fsEcg, dur: durEcg, fc: patron.fc);
  }

  // Actividad auricular continua (flutter/fib)
  final basal = ritmo.basal;
  if (basal != null) {
    for (final nombre in ordenDerivaciones) {
      basal(derivaciones[nombre]!, nombre);
    }
  }

  // Ondas P
  for (final nombre in ordenDerivaciones) {
    for (final tP in ritmo.ondasP) {
      _estamparP(derivaciones[nombre]!, tP, l[nombre]!, tm);
    }
  }

  // Latidos
  final ev = _derivacionesEv();
  for (final b in ritmo.latidos) {
    for (final nombre in ordenDerivaciones) {
      var w = l[nombre]!;
      var bt = tm;
      if (b.tipo == _TipoLatido.pvc) w = ev[nombre]!;
      if (ritmo.polimorfico) {
        // Torsade: amplitud/eje modulados en huso alrededor de la línea base
        final env = math.sin(2 * math.pi * 0.3 * b.t);
        final signo = _o(_sign(env), 1);
        final amp = (0.4 + env.abs() * 1.3) * signo;
        w = l[nombre]!.copia()
          ..q = 0
          ..r = amp
          ..s = -amp * 0.5
          ..rp = 0
          ..t = 0
          ..j = 0
          ..u = 0
          ..delta = 0
          ..notch = 0;
        bt = tm.conQrs(2.0);
      }
      _estamparLatido(derivaciones[nombre]!, b.t, w, bt);
    }
  }

  return SintesisEcg(
    derivaciones: derivaciones,
    latidos: [for (final b in ritmo.latidos) b.t],
    fs: fsEcg,
    dur: durEcg,
    fc: patron.fc,
  );
}

/// El voltaje en el instante [t] (s), dando la vuelta a la tira de 10 s como la web.
double voltajeEn(Float32List buf, double t, {int fs = fsEcg, int dur = durEcg}) {
  final i = ((((t % dur) + dur) % dur) * fs).floor();
  return i >= 0 && i < buf.length ? buf[i] : 0;
}

/// ¿Ha pasado una R entre [tPrevio] y [tAhora] (con la vuelta de la tira)? Devuelve su índice, o null.
/// Es el `onBeat` del RhythmMonitor de la web: no repite el último que avisó.
int? latidoCruzado(List<double> latidos, double tPrevio, double tAhora, int? ultimo, {int dur = durEcg}) {
  final tb = tAhora % dur;
  final tbPrev = tPrevio % dur;
  for (var k = 0; k < latidos.length; k++) {
    final bt = latidos[k];
    final cruzado = (tbPrev <= bt && tb >= bt) || (tb < tbPrev && (bt >= tbPrev || bt <= tb));
    if (cruzado && k != ultimo) return k;
  }
  return null;
}

/* ════════════════════════════════════════════════════════════════════════
   Modo examen (patterns.ts y ExploradorClient.tsx)
═══════════════════════════════════════════════════════════════════════════ */

const String _conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
const String _sinTilde = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';

/// Quita acentos y signos para comparar lo que escribe el alumno (normalizeAnswer de la web: NFD y
/// fuera las marcas; Dart no trae NFD, así que se mapean las letras con tilde del español).
String normalizarRespuesta(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = _conTilde.indexOf(c);
    b.write(i >= 0 ? _sinTilde[i] : c);
  }
  return b
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// El buscador del modo examen: hasta 6, primero la coincidencia exacta y después los términos donde
/// lo escrito aparece antes. Empates, por nombre.
List<PatronEcg> buscarPatrones(String consulta, List<PatronEcg> patrones) {
  final nq = normalizarRespuesta(consulta);
  if (nq.isEmpty) return const [];
  final puntuados = <({PatronEcg p, int mejor})>[];
  for (final p in patrones) {
    int? mejor;
    for (final termino in p.busqueda) {
      final nt = normalizarRespuesta(termino);
      final idx = nt.indexOf(nq);
      if (idx >= 0) {
        final v = idx + (nt == nq ? -100 : 0);
        mejor = mejor == null ? v : math.min(mejor, v);
      }
    }
    if (mejor != null) puntuados.add((p: p, mejor: mejor));
  }
  puntuados.sort((a, b) {
    final c = a.mejor.compareTo(b.mejor);
    return c != 0 ? c : a.p.nombre.compareTo(b.p.nombre);
  });
  return [for (final s in puntuados.take(6)) s.p];
}

/// El patrón cuyo nombre es exactamente lo escrito (escribirlo a mano también vale como elección).
PatronEcg? patronPorNombreExacto(String texto, List<PatronEcg> patrones) {
  final n = normalizarRespuesta(texto);
  for (final p in patrones) {
    if (normalizarRespuesta(p.nombre) == n) return p;
  }
  return null;
}

const int largoExamenEcg = 10;

/// Una tanda del examen: 10 patrones barajados (Fisher-Yates, como la web).
List<PatronEcg> barajarExamen(List<PatronEcg> patrones, math.Random azar) {
  final a = [...patrones];
  for (var i = a.length - 1; i > 0; i--) {
    final j = azar.nextInt(i + 1);
    final x = a[i];
    a[i] = a[j];
    a[j] = x;
  }
  return a.take(largoExamenEcg).toList();
}

/// El mensaje del final del examen, según el porcentaje (QuizResults de la web).
({String emoji, String mensaje, GravedadEcg tono}) resultadoExamen(int aciertos) {
  final pct = (aciertos / largoExamenEcg * 100).round();
  if (pct == 100) return (emoji: '🏆', mensaje: '¡Perfecto! Dominas los patrones del MIR.', tono: GravedadEcg.normal);
  if (pct >= 70) {
    return (
      emoji: '🫀',
      mensaje: '$aciertos de $largoExamenEcg aciertos. Muy buen nivel, repasa los fallos.',
      tono: GravedadEcg.normal,
    );
  }
  if (pct >= 40) {
    return (
      emoji: '📈',
      mensaje: '$aciertos de $largoExamenEcg. Vas por buen camino; vuelve al explorador para afianzar.',
      tono: GravedadEcg.warn,
    );
  }
  return (
    emoji: '📖',
    mensaje: '$aciertos de $largoExamenEcg. Repasa los patrones en el explorador y vuelve a intentarlo.',
    tono: GravedadEcg.crit,
  );
}
