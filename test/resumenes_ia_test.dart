import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/core/models/resumen_ia.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_api.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_guardado.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_ia.dart';

final _h1 = 'a' * 64;
final _h2 = 'b' * 64;

FuenteFirmada _fuente(String hash) => FuenteFirmada(hash: hash, caracteres: 1000, firma: 'c' * 64);

ParrafoBorrador _p(String key, {String? doc, bool incluir = true, bool incluirParecido = false, String texto = 'La anemia ferropénica es frecuente'}) => ParrafoBorrador(
      key: key,
      tema: 'General',
      texto: texto,
      huecos: const [Hueco(3, 9, 2)],
      incluir: incluir,
      doc: doc,
      incluirParecido: incluirParecido,
    );

void main() {
  group('sanearFuente', () {
    test('acepta una fuente válida y rechaza las rotas', () {
      expect(sanearFuente({'hash': _h1, 'caracteres': 100, 'firma': _h1}), isNotNull);
      expect(sanearFuente({'hash': 'no-hex', 'caracteres': 100, 'firma': _h1}), isNull);
      expect(sanearFuente({'hash': _h1, 'caracteres': 0, 'firma': _h1}), isNull);
      expect(sanearFuente({'hash': _h1, 'caracteres': 100, 'firma': 'corta'}), isNull);
    });
  });

  group('sanearParrafoBorrador', () {
    test('descarta lo que no tiene huecos o texto', () {
      expect(sanearParrafoBorrador({'texto': 'La anemia ferropénica es frecuente', 'huecos': [{'i': 3, 'f': 9, 'n': 2}]}, 'k'), isNotNull);
      expect(sanearParrafoBorrador({'texto': 'La anemia ferropénica es frecuente', 'huecos': []}, 'k'), isNull);
      expect(sanearParrafoBorrador({'texto': 'x', 'huecos': [{'i': 0, 'f': 1, 'n': 2}]}, 'k'), isNull);
    });
  });

  group('seGuarda', () {
    test('solo lo marcado y, si se parece, con «incluir igual»', () {
      expect(seGuarda(_p('a'), null), isTrue);
      expect(seGuarda(_p('a', incluir: false), null), isFalse);
      expect(seGuarda(_p('a'), const Parecido(igual: true, texto: 'x')), isFalse);
      expect(seGuarda(_p('a', incluirParecido: true), const Parecido(igual: true, texto: 'x')), isTrue);
    });
  });

  group('literalPorDocumento', () {
    test('solo cuenta en modo literal y por documento', () {
      final lista = [_p('a', doc: _h1), _p('b', doc: _h1), _p('c')];
      final r = literalPorDocumento(lista, ModoResumen.literal, const {});
      expect(r[_h1], 'La anemia ferropénica es frecuente'.length * 2);
      expect(r.containsKey(_h2), isFalse);
    });
  });

  group('tandasDeGuardado', () {
    test('agrupa por documento y marca los parecidos incluidos', () {
      final lista = [
        _p('a', doc: _h1),
        _p('b', doc: _h1, incluirParecido: true),
        _p('c', doc: _h2),
      ];
      final parecidos = {'b': const Parecido(igual: true, texto: 'x')};
      final tandas = tandasDeGuardado(
        lista,
        (p) => ParrafoNuevo(texto: p.texto, huecos: p.huecos, tema: p.tema),
        [_fuente(_h1), _fuente(_h2)],
        parecidos,
      );
      expect(tandas.length, 2);
      expect(tandas[0].fuente!.hash, _h1);
      expect(tandas[0].parrafos.length, 2);
      expect(tandas[0].incluirParecidos, [1]);
      expect(tandas[1].fuente!.hash, _h2);
      expect(tandas[1].parrafos.length, 1);
    });
  });

  group('excesosLiteral', () {
    test('señala los documentos que se pasan del tope', () {
      expect(excesosLiteral({_h1: 500}, [UsoLiteral(hash: _h1, usado: 400, tope: 1000)]), isEmpty);
      final sobre = excesosLiteral({_h1: 500}, [UsoLiteral(hash: _h1, usado: 900, tope: 1000)]);
      expect(sobre.single.sobran, 400);
    });
  });
}
