-- ============================================================================
-- Asignatura de pruebas: casos raros que en el temario real salen por azar
-- y que hay que poder reproducir a voluntad.
--
--   Enunciado larguísimo · imagen válida · imagen rota · has_image sin url
--   · anuladas · palabra sin espacios · control normal
--
-- Ejecutar: pegar entero en el SQL Editor de Supabase. Es IDEMPOTENTE: si ya
-- existe la asignatura, borra sus preguntas y las vuelve a crear, así que se
-- puede relanzar sin duplicar nada.
--
-- Para BORRARLO todo, al final del archivo hay un bloque comentado.
--
-- ─── Por qué NO aparecen en el daily ────────────────────────────────────────
-- El daily es UNA selección compartida por todos los usuarios y se elige de
-- TODAS las preguntas, sin filtrar por asignatura (`src/cron/dailySelection.js`).
-- Con ~313 preguntas disponibles, cada una de estas tendría ~1,6 % de salirle
-- a todo el mundo cada día.
--
-- El selector descarta lo que aparezca en `question_usage` de los últimos 6
-- meses, así que al final se registran ahí con la fecha de hoy. No hace falta
-- tocar el backend. El "fallback" que reutiliza preguntas usadas solo se activa
-- si quedan menos de 5 disponibles, cosa que no va a pasar.
--
-- OJO: pasados 6 meses dejarían de estar excluidas. Si en esa fecha siguen
-- haciendo falta, relanzar este archivo (vuelve a sellar la fecha).
-- ============================================================================

DO $$
DECLARE
  v_subject_id  bigint;
  v_topic_id    bigint;
  v_qid         integer;
  -- Una imagen que sí existe en R2, copiada de una pregunta real.
  c_img_ok      text := 'https://pub-a0af2de03fec4dd2b89a37964efd1716.r2.dev/questions/2022/20.png';
  -- Una que no existe: sirve para probar el aviso de "no se pudo cargar" y el
  -- botón de reintentar.
  c_img_rota    text := 'https://pub-a0af2de03fec4dd2b89a37964efd1716.r2.dev/questions/9999/999.png';
  c_tags_ok     jsonb := '{"anulada":"No","dificultad":"media","stem_type":"pregunta_directa","image_type":"ninguna","body_system":"no_aplica","patient_sex":"no_especificado","drug_presence":"ninguno","primary_intent":"diagnóstico","question_style":"correcta","clinical_setting":"no_aplica","patient_age_group":"no_aplica"}'::jsonb;
  c_tags_anul   jsonb := '{"anulada":"Sí","dificultad":"media","stem_type":"pregunta_directa","image_type":"ninguna","body_system":"no_aplica","patient_sex":"no_especificado","drug_presence":"ninguno","primary_intent":"diagnóstico","question_style":"correcta","clinical_setting":"no_aplica","patient_age_group":"no_aplica"}'::jsonb;
BEGIN

  -- ── Asignatura y tema ────────────────────────────────────────────────────
  -- El prefijo "ZZZ" la manda al final de cualquier lista ordenada por nombre,
  -- y el paréntesis avisa de lo que es: sale en el selector de asignaturas del
  -- creador de simulacros de TODOS los usuarios.
  SELECT id INTO v_subject_id FROM subjects WHERE name = 'ZZZ · Pruebas (no estudiar)';
  IF v_subject_id IS NULL THEN
    INSERT INTO subjects (name) VALUES ('ZZZ · Pruebas (no estudiar)') RETURNING id INTO v_subject_id;
  END IF;

  SELECT id INTO v_topic_id FROM topics WHERE subject_id = v_subject_id AND name = 'Casos límite';
  IF v_topic_id IS NULL THEN
    INSERT INTO topics (subject_id, name) VALUES (v_subject_id, 'Casos límite') RETURNING id INTO v_topic_id;
  END IF;

  -- ── Limpieza previa, para poder relanzar ────────────────────────────────
  DELETE FROM question_usage
   WHERE question_id IN (SELECT id FROM questions WHERE subject_id = v_subject_id);
  DELETE FROM question_options
   WHERE question_id IN (SELECT id FROM questions WHERE subject_id = v_subject_id);
  DELETE FROM questions WHERE subject_id = v_subject_id;

  -- ══ 1. Enunciado larguísimo, opciones largas y explicación larga ═════════
  -- Para qué: desbordes de texto, el tope de altura de la explicación en el
  -- estudio de mazos, el recorte a 2 líneas en los listados y el scroll.
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 1, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — ENUNCIADO LARGO. Varón de 68 años, exfumador de 40 paquetes-año, con antecedentes de '
    'hipertensión arterial de larga evolución en tratamiento con enalapril, diabetes mellitus tipo 2 '
    'con mal control metabólico (HbA1c 8,9 %), dislipemia, enfermedad renal crónica estadio 3a, '
    'fibrilación auricular permanente anticoagulada con acenocumarol e ingreso hace seis meses por '
    'insuficiencia cardíaca descompensada, que acude al servicio de urgencias por un cuadro de '
    'disnea progresiva de tres semanas de evolución que ha pasado de ser de grandes esfuerzos a '
    'aparecer en reposo, acompañada de ortopnea de tres almohadas, episodios de disnea paroxística '
    'nocturna, edemas maleolares bilaterales con fóvea hasta la rodilla, aumento de 6 kg de peso, '
    'oliguria en las últimas 48 horas y sensación de plenitud abdominal. En la exploración física '
    'destaca una presión arterial de 96/58 mmHg, frecuencia cardíaca de 118 lpm arrítmica, '
    'saturación de oxígeno del 88 % con aire ambiente, ingurgitación yugular a 45 grados, reflujo '
    'hepatoyugular positivo, crepitantes hasta campos medios en ambos hemitórax, hepatomegalia '
    'dolorosa de 4 cm bajo el reborde costal y frialdad acra con relleno capilar enlentecido. '
    'La analítica muestra creatinina de 2,4 mg/dL (previa 1,5), sodio 128 mEq/L, NT-proBNP de '
    '11.400 pg/mL, lactato 3,2 mmol/L y troponina levemente elevada sin curva. ¿Cuál de las '
    'siguientes actitudes terapéuticas le parece MÁS adecuada como primer paso en este paciente?',
    2,
    'PRUEBA — EXPLICACIÓN LARGA. El paciente presenta un perfil hemodinámico "húmedo y frío": '
    'congestión evidente (ingurgitación yugular, crepitantes, edemas, hepatomegalia, NT-proBNP muy '
    'elevado) junto a signos de bajo gasto (hipotensión relativa, frialdad acra, relleno capilar '
    'enlentecido, hiperlactatemia y deterioro de la función renal). En este escenario, administrar '
    'diuréticos de asa en monoterapia a dosis altas puede empeorar la perfusión tisular y precipitar '
    'un síndrome cardiorrenal tipo 1, mientras que los vasodilatadores están limitados por la '
    'presión arterial. La estrategia correcta pasa por asociar un inotrópico que restaure la '
    'perfusión y permita después una descongestión eficaz, monitorizando estrechamente la diuresis, '
    'la función renal y los iones. La hiponatremia dilucional y la elevación discreta de troponina '
    'sin curva son hallazgos esperables en este contexto y no cambian la actitud inicial. '
    'Recuerde que en la insuficiencia cardíaca avanzada el orden de las intervenciones importa '
    'tanto como las intervenciones mismas.',
    false, NULL, v_subject_id, v_topic_id, c_tags_ok)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'Administrar furosemida en perfusión continua a dosis altas como única medida inicial, asumiendo que la mejoría de la congestión corregirá por sí sola la hipoperfusión periférica y el deterioro de la función renal.'),
    (v_qid, 2, 'Iniciar soporte inotrópico con dobutamina y, una vez recuperada la perfusión, asociar diurético de asa intravenoso con monitorización estrecha de diuresis, función renal e iones.'),
    (v_qid, 3, 'Comenzar con nitroglicerina intravenosa a dosis crecientes para reducir la precarga, dado que la congestión pulmonar es el hallazgo predominante en la exploración física.'),
    (v_qid, 4, 'Suspender la anticoagulación oral e iniciar heparina sódica en perfusión, a la espera de realizar una coronariografía urgente por la elevación de troponina.');

  -- ══ 2. Imagen que SÍ existe ══════════════════════════════════════════════
  -- Para qué: la página "IMAGEN" del simulacro en modo deslizar, el visor a
  -- pantalla completa y el zoom.
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 2, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — IMAGEN CORRECTA. Esta pregunta tiene una imagen que sí existe en el bucket. '
    'Debe verse tanto en línea como al ampliarla. ¿Cuál es la respuesta correcta?',
    1, 'PRUEBA. La imagen debería haberse visto sin problemas.',
    true, c_img_ok, v_subject_id, v_topic_id, c_tags_ok)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'Opción A (correcta)'), (v_qid, 2, 'Opción B'),
    (v_qid, 3, 'Opción C'), (v_qid, 4, 'Opción D');

  -- ══ 3. Imagen que NO existe ══════════════════════════════════════════════
  -- Para qué: el aviso "No se pudo cargar la imagen" y el botón Reintentar.
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 3, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — IMAGEN ROTA. La URL de esta pregunta apunta a un fichero que no existe. '
    'Debe salir el aviso de que no se pudo cargar, con botón de Reintentar, NO un hueco vacío.',
    1, 'PRUEBA. Si has visto un hueco en blanco sin mensaje, el arreglo no está aplicado.',
    true, c_img_rota, v_subject_id, v_topic_id, c_tags_ok)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'Opción A (correcta)'), (v_qid, 2, 'Opción B'),
    (v_qid, 3, 'Opción C'), (v_qid, 4, 'Opción D');

  -- ══ 4. has_image = true pero SIN url ═════════════════════════════════════
  -- Para qué: reproduce un caso REAL de producción (hay 1 pregunta así en
  -- Digestivo). La app no debe romperse ni dejar hueco.
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 4, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — DICE TENER IMAGEN PERO NO LA TIENE. has_image está a true y image_url a null, '
    'igual que una pregunta real de Digestivo. No debe romper nada ni dejar un hueco.',
    3, 'PRUEBA. Lo correcto es que se comporte como una pregunta sin imagen.',
    true, NULL, v_subject_id, v_topic_id, c_tags_ok)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'Opción A'), (v_qid, 2, 'Opción B'),
    (v_qid, 3, 'Opción C (correcta)'), (v_qid, 4, 'Opción D');

  -- ══ 5. Anulada ═══════════════════════════════════════════════════════════
  -- Para qué: el distintivo de anulada. Recordatorio: las anuladas NO entran
  -- en el daily por diseño, pero SÍ pueden salir en simulacros y mazos.
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 5, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — ANULADA. Esta pregunta está marcada como anulada en analytics_tags. '
    'Debe salir señalada como tal donde la app lo contemple.',
    1, 'PRUEBA. Anulada por el Ministerio en su día; se mantiene por interés docente.',
    false, NULL, v_subject_id, v_topic_id, c_tags_anul)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'Opción A (la que se dio por buena)'), (v_qid, 2, 'Opción B'),
    (v_qid, 3, 'Opción C'), (v_qid, 4, 'Opción D');

  -- ══ 6. Anulada Y con imagen ══════════════════════════════════════════════
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 6, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — ANULADA CON IMAGEN. Las dos cosas a la vez, por si el distintivo de anulada '
    'y la página de imagen se pisan entre ellas.',
    2, 'PRUEBA. Deben convivir el aviso de anulada y la imagen.',
    true, c_img_ok, v_subject_id, v_topic_id, c_tags_anul)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'Opción A'), (v_qid, 2, 'Opción B (correcta)'),
    (v_qid, 3, 'Opción C'), (v_qid, 4, 'Opción D');

  -- ══ 7. Palabra larguísima sin espacios ═══════════════════════════════════
  -- Para qué: el corte de palabras. Es el caso que ya rompió la tarjeta de la
  -- galería de mazos cuando una bio no tenía espacios.
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 7, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — PALABRA SIN ESPACIOS. El término es '
    'pseudopseudohipoparatiroidismoconhipercolesterolemiafamiliarhomocigotaydisplasiabroncopulmonar '
    'y no debe salirse de ninguna caja. Sirve también para probar el resaltado del buscador: '
    'busca "hipo" en el mazo donde la guardes.',
    4, 'PRUEBA. Ninguna caja debería desbordarse por esa palabra.',
    false, NULL, v_subject_id, v_topic_id, c_tags_ok)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'antidisestablishmentarianismohipercolesterolemicoconstitucional'),
    (v_qid, 2, 'Opción B'), (v_qid, 3, 'Opción C'),
    (v_qid, 4, 'Opción D (correcta)');

  -- ══ 8. Control: corta y normal ═══════════════════════════════════════════
  -- Para qué: comparar. Si algo se ve raro también aquí, no es un caso límite.
  INSERT INTO questions (year, question_number, subject, topic, statement, correct_answer,
                         explanation, has_image, image_url, subject_id, topic_id, analytics_tags)
  VALUES (2099, 8, 'ZZZ · Pruebas (no estudiar)', 'Casos límite',
    'PRUEBA — CONTROL. Pregunta corta y sin nada raro. ¿Cuál es la opción correcta?',
    1, 'PRUEBA. Es la A.',
    false, NULL, v_subject_id, v_topic_id, c_tags_ok)
  RETURNING id INTO v_qid;
  INSERT INTO question_options (question_id, option_index, option_text) VALUES
    (v_qid, 1, 'La A (correcta)'), (v_qid, 2, 'La B'),
    (v_qid, 3, 'La C'), (v_qid, 4, 'La D');

  -- ── Fuera del daily ──────────────────────────────────────────────────────
  -- Se marcan como "ya usadas hoy": el selector del daily descarta todo lo que
  -- haya aparecido en los últimos 6 meses.
  INSERT INTO question_usage (question_id, used_date, usage_type)
  SELECT id, current_date, 'daily' FROM questions WHERE subject_id = v_subject_id;

  RAISE NOTICE 'Asignatura de pruebas lista: subject_id=%, topic_id=%', v_subject_id, v_topic_id;
END $$;

-- Comprobación
SELECT q.id, q.question_number AS n, q.has_image,
       (q.analytics_tags->>'anulada') AS anulada,
       length(q.statement) AS largo_enunciado,
       (q.image_url IS NOT NULL) AS tiene_url,
       (SELECT count(*) FROM question_options o WHERE o.question_id = q.id) AS opciones
  FROM questions q
  JOIN subjects s ON s.id = q.subject_id
 WHERE s.name = 'ZZZ · Pruebas (no estudiar)'
 ORDER BY q.question_number;


-- ============================================================================
-- BORRARLO TODO (descomentar y ejecutar)
-- ============================================================================
-- DO $$
-- DECLARE v_subject_id bigint;
-- BEGIN
--   SELECT id INTO v_subject_id FROM subjects WHERE name = 'ZZZ · Pruebas (no estudiar)';
--   IF v_subject_id IS NULL THEN RAISE NOTICE 'No existe, nada que borrar'; RETURN; END IF;
--   DELETE FROM deck_items WHERE question_id IN (SELECT id FROM questions WHERE subject_id = v_subject_id);
--   DELETE FROM user_responses WHERE question_id IN (SELECT id FROM questions WHERE subject_id = v_subject_id);
--   DELETE FROM question_usage  WHERE question_id IN (SELECT id FROM questions WHERE subject_id = v_subject_id);
--   DELETE FROM question_options WHERE question_id IN (SELECT id FROM questions WHERE subject_id = v_subject_id);
--   DELETE FROM questions WHERE subject_id = v_subject_id;
--   DELETE FROM topics    WHERE subject_id = v_subject_id;
--   DELETE FROM subjects  WHERE id = v_subject_id;
--   RAISE NOTICE 'Asignatura de pruebas eliminada';
-- END $$;
