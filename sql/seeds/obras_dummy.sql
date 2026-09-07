-- ============================================================
-- Datos de prueba de Agenda de Obras. NO es una migración y no va a
-- producción: sirve para recorrer el módulo a mano y auditar el modelo de
-- visibilidad con datos que se parecen a los reales.
--
-- Ids fijos con prefijo reconocible (`b0…` obras, `e0…` empresas, `c0…`
-- personas, y las tablas puente con el suyo) por dos razones: se puede volver
-- a correr sin duplicar nada (`ON CONFLICT (id) DO NOTHING`), y borrarlo todo
-- es un DELETE por prefijo — ver `obras_dummy_borrar.sql`. Ese DELETE es la
-- excepción a "nunca DELETE" que se permite acá: no son filas de negocio.
--
-- Corre como dueño de la base (MCP / dashboard), sin RLS de por medio. No
-- pasa por `obras_transferir` ni por `obras_ficha_persona()`: las filas de
-- `obras_transferencias` y `obras_accesos_persona` se escriben directo para
-- que los dos logs tengan qué mostrar.
--
-- Qué queda armado, además del volumen:
--   · 14 obras repartidas entre Admin (9) y Tester (5) — el eje del modelo de
--     visibilidad es `responsable_id`, así que sin dos carteras no hay nada
--     que auditar.
--   · Tres pares casi duplicados, uno por cada función de búsqueda difusa:
--     empresa (`Constructora del Plata S.A.` / `… SA`), obra (`Nogoyá 3400`
--     de Admin / `Nogoya 3400` de Tester, que es el aviso ciego) y persona
--     (`Juan Pérez` de Admin / `Juan Perez` de Tester).
--   · Una obra sin dirección, sin empresas y sin personas (Casa Quinta
--     Funes): la ficha vacía es un estado válido y hay que poder verla.
--   · Las dos formas de obra perdida: motivo que se explica solo (precio) y
--     `otro`, que exige detalle.
--   · Una obra desactivada, una empresa desactivada sin obras y una persona
--     desactivada, para que los listados tengan algo que filtrar.
--   · Un referente con dos comisiones distintas en dos obras — la comisión es
--     de la relación, no de la persona.
--   · Teléfonos escritos de seis formas distintas, para ver la normalización.
-- ============================================================

-- ---------- Empresas ----------
INSERT INTO obras_empresas (id, razon_social, nombre_comercial, website, telefono, email, direccion, localidad, provincia, creado_por, activo) VALUES
  ('e0000000-0000-4000-a000-000000000001', 'Constructora del Plata S.A.', 'Del Plata', 'https://delplata.com.ar', '011 4785-2200', 'contacto@delplata.com.ar', 'Av. Córdoba 1450', 'CABA', 'caba', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('e0000000-0000-4000-a000-000000000002', 'Constructora del Plata SA', NULL, NULL, '+54 11 4785 2200', NULL, NULL, 'Capital', 'caba', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('e0000000-0000-4000-a000-000000000003', 'Desarrollos Nogoyá S.R.L.', 'Grupo Nogoyá', 'https://gruponogoya.com', '1145507788', 'info@gruponogoya.com', 'Nogoyá 3390', 'Villa Devoto', 'caba', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('e0000000-0000-4000-a000-000000000004', 'Estudio Bianchi Arquitectos', 'Bianchi Arq.', 'https://bianchiarq.com.ar', '11 6023-4411', 'estudio@bianchiarq.com.ar', 'Honduras 5250', 'Palermo', 'caba', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('e0000000-0000-4000-a000-000000000005', 'Vega + Asociados', 'Vega Asoc.', NULL, '0351 452-9080', 'hola@vegaasociados.ar', 'Bv. Chacabuco 780', 'Córdoba', 'cordoba', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('e0000000-0000-4000-a000-000000000006', 'Inmobiliaria Costa Norte S.R.L.', 'Costa Norte Propiedades', NULL, '(0348) 442-1177', 'ventas@costanorte.com.ar', 'Av. del Puerto 210', 'Escobar', 'buenos_aires', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('e0000000-0000-4000-a000-000000000007', 'Fassi Dirección de Obra', NULL, NULL, '341 615-3300', 'jfassi@fassiobra.com', NULL, 'Rosario', 'santa_fe', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('e0000000-0000-4000-a000-000000000008', 'Vivienda Sur S.A.', 'Vivienda Sur', 'https://viviendasur.com.ar', '299 447-8890', NULL, 'Av. Argentina 1120', 'Neuquén', 'neuquen', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('e0000000-0000-4000-a000-000000000009', 'Hotelera Andina S.A.', NULL, NULL, NULL, 'proyectos@hoteleraandina.com', NULL, 'Mendoza', 'mendoza', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('e0000000-0000-4000-a000-000000000010', 'Constructora Rivas e Hijos', 'Rivas', NULL, '11 4300-1122', NULL, NULL, 'Avellaneda', 'buenos_aires', '015fa985-fe21-4434-b3c5-7ac78732d765', false)
ON CONFLICT (id) DO NOTHING;

-- ---------- Personas ----------
INSERT INTO obras_personas (id, nombre, apellido, telefono, whatsapp, email, creado_por, activo) VALUES
  ('c0000000-0000-4000-a000-000000000001', 'Martín',   'Bianchi',  '11 6023-4412', '+54 9 11 6023-4412', 'mbianchi@bianchiarq.com.ar', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000002', 'Lucía',    'Ferreyra', '(011) 4785-2210', '1167890011', 'lferreyra@delplata.com.ar', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000003', 'Juan',     'Pérez',    '11 4550-7789', NULL, 'jperez@gruponogoya.com', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000004', 'Juan',     'Perez',    '+54 11 4550 7789', NULL, NULL, '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('c0000000-0000-4000-a000-000000000005', 'Sofía',    'Ramírez',  '11 5544-8899', '11 5544-8899', 'sramirez@delplata.com.ar', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000006', 'Diego',    'Vega',     '0351 452-9081', NULL, 'dvega@vegaasociados.ar', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000007', 'Carolina', 'Sosa',     '11 6712-3344', '+5491167123344', 'csosa@costanorte.com.ar', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000008', 'Roberto',  'Iglesias', '11 4788-1200', NULL, 'riglesias@gruponogoya.com', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000009', 'Valeria',  'Kaufman',  '11 3355-9090', NULL, 'vkaufman@hoteleraandina.com', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('c0000000-0000-4000-a000-000000000010', 'Néstor',   'Almada',   '11 4300-1123', NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', false),
  ('c0000000-0000-4000-a000-000000000011', 'Javier',   'Fassi',    '341 615-3301', '3416153301', 'jfassi@fassiobra.com', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('c0000000-0000-4000-a000-000000000012', 'Mariana',  'Ledesma',  '299 447-8891', NULL, 'mledesma@viviendasur.com.ar', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('c0000000-0000-4000-a000-000000000013', 'Alberto',  'Quiroga',  '341 500-2277', NULL, NULL, '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('c0000000-0000-4000-a000-000000000014', 'Paula',    'Ibarra',   '11 6688-4400', '+54 9 11 6688 4400', 'pibarra@estudioibarra.com', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('c0000000-0000-4000-a000-000000000015', 'Gustavo',  'Peralta',  '299 500-1188', NULL, 'gperalta@clinicaneuquen.com.ar', '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('c0000000-0000-4000-a000-000000000016', 'Silvina',  'Roldán',   NULL, NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true)
ON CONFLICT (id) DO NOTHING;

-- ---------- Personas ↔ empresas ----------
-- `es_principal` como máximo una por persona (unique index parcial).
INSERT INTO obras_persona_empresa (id, persona_id, empresa_id, cargo, es_principal, observaciones, activo) VALUES
  ('a1000000-0000-4000-a000-000000000001', 'c0000000-0000-4000-a000-000000000001', 'e0000000-0000-4000-a000-000000000004', 'Socio fundador', true, NULL, true),
  ('a1000000-0000-4000-a000-000000000002', 'c0000000-0000-4000-a000-000000000002', 'e0000000-0000-4000-a000-000000000001', 'Jefa de compras', true, 'Pide siempre tres presupuestos', true),
  ('a1000000-0000-4000-a000-000000000003', 'c0000000-0000-4000-a000-000000000003', 'e0000000-0000-4000-a000-000000000003', 'Gerente de proyectos', true, NULL, true),
  ('a1000000-0000-4000-a000-000000000004', 'c0000000-0000-4000-a000-000000000005', 'e0000000-0000-4000-a000-000000000001', 'Oficina técnica', true, NULL, true),
  ('a1000000-0000-4000-a000-000000000005', 'c0000000-0000-4000-a000-000000000006', 'e0000000-0000-4000-a000-000000000005', 'Director', true, NULL, true),
  ('a1000000-0000-4000-a000-000000000006', 'c0000000-0000-4000-a000-000000000007', 'e0000000-0000-4000-a000-000000000006', 'Comercial zona norte', true, NULL, true),
  ('a1000000-0000-4000-a000-000000000007', 'c0000000-0000-4000-a000-000000000008', 'e0000000-0000-4000-a000-000000000003', 'Dueño', true, 'Decide él, aunque delegue', true),
  ('a1000000-0000-4000-a000-000000000008', 'c0000000-0000-4000-a000-000000000009', 'e0000000-0000-4000-a000-000000000009', 'Gerenta de expansión', true, NULL, true),
  ('a1000000-0000-4000-a000-000000000009', 'c0000000-0000-4000-a000-000000000011', 'e0000000-0000-4000-a000-000000000007', 'Director de obra', true, NULL, true),
  ('a1000000-0000-4000-a000-000000000010', 'c0000000-0000-4000-a000-000000000012', 'e0000000-0000-4000-a000-000000000008', 'Compras', true, NULL, true),
  -- Segunda empresa, no principal: el arquitecto también trabaja para la desarrolladora.
  ('a1000000-0000-4000-a000-000000000011', 'c0000000-0000-4000-a000-000000000001', 'e0000000-0000-4000-a000-000000000003', 'Proyectista externo', false, NULL, true),
  ('a1000000-0000-4000-a000-000000000012', 'c0000000-0000-4000-a000-000000000014', 'e0000000-0000-4000-a000-000000000008', 'Arquitecta contratada', false, NULL, true)
ON CONFLICT (id) DO NOTHING;

-- ---------- Obras ----------
-- 9 de Admin, 5 de Tester. Los `_norm` los pone el trigger.
INSERT INTO obras (id, nombre, tipo, estado, direccion, localidad, provincia, origen, observaciones, motivo_perdida, detalle_perdida, responsable_id, activo) VALUES
  ('b0000000-0000-4000-a000-000000000001', 'Edificio Nogoyá 3400', 'edificio', 'en_construccion', 'Nogoyá 3400', 'Villa Devoto', 'caba', 'arquitecto', 'Losa del 4º piso en septiembre. El pedido grande entra por Ferreyra.', NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000002', 'Torre Vicente López', 'edificio', 'idea', 'Av. del Libertador 2100', 'Vicente López', 'buenos_aires', 'referido', 'Todavía en anteproyecto.', NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000003', 'Casa Los Álamos', 'casa', 'en_construccion', 'Los Álamos 145', 'Villa Allende', 'cordoba', 'deteccion_propia', NULL, NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000004', 'Complejo Costa Norte', 'complejo_viviendas', 'idea', 'Ruta 25 km 4', 'Escobar', 'buenos_aires', 'inmobiliaria', '120 unidades en tres etapas.', NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000005', 'Refacción Local Av. Santa Fe', 'refaccion', 'terminada', 'Av. Santa Fe 3200', 'Palermo', 'caba', 'internet', 'Entregada en marzo.', NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000006', 'Hotel Andes Boutique', 'hotel', 'idea', NULL, 'Chacras de Coria', 'mendoza', 'desarrolladora', 'Contacto inicial, sin proyecto todavía.', NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000007', 'Oficinas Catalinas Norte', 'oficina', 'perdida', 'Della Paolera 260', 'Retiro', 'caba', 'constructora', NULL, 'precio', NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000008', 'Local Palermo Soho', 'local', 'perdida', 'Gurruchaga 1800', 'Palermo', 'caba', 'referido', NULL, 'otro', 'El cliente puso la obra en pausa por tiempo indeterminado; no hubo competencia.', '015fa985-fe21-4434-b3c5-7ac78732d765', true),
  ('b0000000-0000-4000-a000-000000000009', 'Depósito Zona Sur', 'otro', 'idea', 'Camino Gral. Belgrano 4500', 'Quilmes', 'buenos_aires', 'otro', 'Cargada por error, se archiva.', NULL, NULL, '015fa985-fe21-4434-b3c5-7ac78732d765', false),
  ('b0000000-0000-4000-a000-000000000010', 'Edificio Nogoya 3400', 'edificio', 'idea', 'Nogoya 3400', 'Devoto', 'caba', 'deteccion_propia', 'La vi de la calle, averiguar quién construye.', NULL, NULL, '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('b0000000-0000-4000-a000-000000000011', 'Barrio Cerrado Los Robles', 'complejo_viviendas', 'en_construccion', 'Ruta 8 km 62', 'Pilar', 'buenos_aires', 'desarrolladora', '48 lotes con casa incluida.', NULL, NULL, '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('b0000000-0000-4000-a000-000000000012', 'Casa Quinta Funes', 'casa', 'idea', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('b0000000-0000-4000-a000-000000000013', 'Ampliación Clínica Neuquén', 'refaccion', 'en_construccion', 'Av. Olascoaga 950', 'Neuquén', 'neuquen', 'arquitecto', 'Obra en dos etapas, con la clínica funcionando.', NULL, NULL, '48b90421-a639-4637-b361-501fa7e1a1a0', true),
  ('b0000000-0000-4000-a000-000000000014', 'Edificio Rosario Centro', 'edificio', 'terminada', 'Córdoba 1450', 'Rosario', 'santa_fe', 'constructora', 'Venía de la cartera de Admin.', NULL, NULL, '48b90421-a639-4637-b361-501fa7e1a1a0', true)
ON CONFLICT (id) DO NOTHING;

-- ---------- Obra ↔ empresa ----------
-- La primera fila es el caso que justifica el array: constructora Y
-- desarrolladora de la misma obra es una relación con dos roles.
INSERT INTO obras_obra_empresa (id, obra_id, empresa_id, roles, observaciones, activo) VALUES
  ('a2000000-0000-4000-a000-000000000001', 'b0000000-0000-4000-a000-000000000001', 'e0000000-0000-4000-a000-000000000001', ARRAY['constructora','desarrolladora']::rol_empresa[], 'Compra centralizada en su oficina técnica', true),
  ('a2000000-0000-4000-a000-000000000002', 'b0000000-0000-4000-a000-000000000001', 'e0000000-0000-4000-a000-000000000004', ARRAY['estudio_arquitectura']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000003', 'b0000000-0000-4000-a000-000000000002', 'e0000000-0000-4000-a000-000000000003', ARRAY['desarrolladora']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000004', 'b0000000-0000-4000-a000-000000000003', 'e0000000-0000-4000-a000-000000000005', ARRAY['estudio_arquitectura','direccion_obra']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000005', 'b0000000-0000-4000-a000-000000000004', 'e0000000-0000-4000-a000-000000000006', ARRAY['inmobiliaria']::rol_empresa[], 'Trae el dato, no compra', true),
  ('a2000000-0000-4000-a000-000000000006', 'b0000000-0000-4000-a000-000000000004', 'e0000000-0000-4000-a000-000000000001', ARRAY['constructora']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000007', 'b0000000-0000-4000-a000-000000000005', 'e0000000-0000-4000-a000-000000000004', ARRAY['estudio_arquitectura']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000008', 'b0000000-0000-4000-a000-000000000006', 'e0000000-0000-4000-a000-000000000009', ARRAY['desarrolladora']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000009', 'b0000000-0000-4000-a000-000000000007', 'e0000000-0000-4000-a000-000000000001', ARRAY['constructora']::rol_empresa[], 'Perdida por precio, la relación sigue', true),
  -- Relación desactivada: el estudio salió de la obra, la fila queda.
  ('a2000000-0000-4000-a000-000000000010', 'b0000000-0000-4000-a000-000000000002', 'e0000000-0000-4000-a000-000000000004', ARRAY['estudio_arquitectura']::rol_empresa[], 'Se bajaron del proyecto', false),
  ('a2000000-0000-4000-a000-000000000011', 'b0000000-0000-4000-a000-000000000011', 'e0000000-0000-4000-a000-000000000008', ARRAY['desarrolladora','constructora']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000012', 'b0000000-0000-4000-a000-000000000013', 'e0000000-0000-4000-a000-000000000007', ARRAY['direccion_obra']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000013', 'b0000000-0000-4000-a000-000000000014', 'e0000000-0000-4000-a000-000000000007', ARRAY['direccion_obra']::rol_empresa[], NULL, true),
  ('a2000000-0000-4000-a000-000000000014', 'b0000000-0000-4000-a000-000000000010', 'e0000000-0000-4000-a000-000000000002', ARRAY['constructora']::rol_empresa[], 'Cargó la empresa duplicada sin saber', true)
ON CONFLICT (id) DO NOTHING;

-- ---------- Obra ↔ persona ----------
-- `empresa_id` es contexto: a quién representa esa persona en esta obra.
INSERT INTO obras_obra_persona (id, obra_id, persona_id, empresa_id, roles, observaciones, activo) VALUES
  ('a3000000-0000-4000-a000-000000000001', 'b0000000-0000-4000-a000-000000000001', 'c0000000-0000-4000-a000-000000000002', 'e0000000-0000-4000-a000-000000000001', ARRAY['compras','decisor']::rol_persona[], 'Firma ella hasta cierto monto', true),
  ('a3000000-0000-4000-a000-000000000002', 'b0000000-0000-4000-a000-000000000001', 'c0000000-0000-4000-a000-000000000001', 'e0000000-0000-4000-a000-000000000004', ARRAY['arquitecto','influenciador']::rol_persona[], 'Especifica marca en el pliego', true),
  ('a3000000-0000-4000-a000-000000000003', 'b0000000-0000-4000-a000-000000000001', 'c0000000-0000-4000-a000-000000000005', 'e0000000-0000-4000-a000-000000000001', ARRAY['oficina_tecnica']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000004', 'b0000000-0000-4000-a000-000000000002', 'c0000000-0000-4000-a000-000000000003', 'e0000000-0000-4000-a000-000000000003', ARRAY['desarrollador','decisor']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000005', 'b0000000-0000-4000-a000-000000000002', 'c0000000-0000-4000-a000-000000000008', 'e0000000-0000-4000-a000-000000000003', ARRAY['inversor']::rol_persona[], 'Aparece solo en las decisiones grandes', true),
  ('a3000000-0000-4000-a000-000000000006', 'b0000000-0000-4000-a000-000000000003', 'c0000000-0000-4000-a000-000000000006', 'e0000000-0000-4000-a000-000000000005', ARRAY['arquitecto','director_obra']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000007', 'b0000000-0000-4000-a000-000000000004', 'c0000000-0000-4000-a000-000000000007', 'e0000000-0000-4000-a000-000000000006', ARRAY['contacto_comercial']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000008', 'b0000000-0000-4000-a000-000000000004', 'c0000000-0000-4000-a000-000000000002', 'e0000000-0000-4000-a000-000000000001', ARRAY['compras']::rol_persona[], 'La misma compradora que en Nogoyá', true),
  ('a3000000-0000-4000-a000-000000000009', 'b0000000-0000-4000-a000-000000000005', 'c0000000-0000-4000-a000-000000000001', 'e0000000-0000-4000-a000-000000000004', ARRAY['arquitecto']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000010', 'b0000000-0000-4000-a000-000000000006', 'c0000000-0000-4000-a000-000000000009', 'e0000000-0000-4000-a000-000000000009', ARRAY['decisor']::rol_persona[], 'Pidió volver a hablar en enero', true),
  ('a3000000-0000-4000-a000-000000000011', 'b0000000-0000-4000-a000-000000000007', 'c0000000-0000-4000-a000-000000000005', 'e0000000-0000-4000-a000-000000000001', ARRAY['oficina_tecnica']::rol_persona[], NULL, true),
  -- Persona sin empresa asignada en la obra: existe y es válido.
  ('a3000000-0000-4000-a000-000000000012', 'b0000000-0000-4000-a000-000000000008', 'c0000000-0000-4000-a000-000000000016', NULL, ARRAY['decisor']::rol_persona[], 'Dueña del local, no representa a nadie', true),
  ('a3000000-0000-4000-a000-000000000013', 'b0000000-0000-4000-a000-000000000011', 'c0000000-0000-4000-a000-000000000012', 'e0000000-0000-4000-a000-000000000008', ARRAY['compras','decisor']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000014', 'b0000000-0000-4000-a000-000000000011', 'c0000000-0000-4000-a000-000000000014', 'e0000000-0000-4000-a000-000000000008', ARRAY['arquitecto']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000015', 'b0000000-0000-4000-a000-000000000013', 'c0000000-0000-4000-a000-000000000015', NULL, ARRAY['decisor','compras']::rol_persona[], 'Administrador de la clínica', true),
  ('a3000000-0000-4000-a000-000000000016', 'b0000000-0000-4000-a000-000000000013', 'c0000000-0000-4000-a000-000000000011', 'e0000000-0000-4000-a000-000000000007', ARRAY['director_obra']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000017', 'b0000000-0000-4000-a000-000000000014', 'c0000000-0000-4000-a000-000000000013', NULL, ARRAY['inversor']::rol_persona[], NULL, true),
  ('a3000000-0000-4000-a000-000000000018', 'b0000000-0000-4000-a000-000000000010', 'c0000000-0000-4000-a000-000000000004', 'e0000000-0000-4000-a000-000000000002', ARRAY['contacto_comercial']::rol_persona[], 'Es el mismo Juan Pérez que ya tenía Admin', true)
ON CONFLICT (id) DO NOTHING;

-- ---------- Referentes y comisión ----------
-- Bianchi es referente en dos obras con porcentajes distintos: la comisión es
-- de la relación, no de la persona.
INSERT INTO obras_obra_referente (id, obra_id, persona_id, porcentaje_comision, observaciones, activo) VALUES
  ('a4000000-0000-4000-a000-000000000001', 'b0000000-0000-4000-a000-000000000001', 'c0000000-0000-4000-a000-000000000001', 3.50, 'Acordado sobre el total del pedido', true),
  ('a4000000-0000-4000-a000-000000000002', 'b0000000-0000-4000-a000-000000000005', 'c0000000-0000-4000-a000-000000000001', 2.00, 'Obra chica, porcentaje menor', true),
  ('a4000000-0000-4000-a000-000000000003', 'b0000000-0000-4000-a000-000000000004', 'c0000000-0000-4000-a000-000000000007', 5.00, 'Trajo el proyecto entero', true),
  ('a4000000-0000-4000-a000-000000000004', 'b0000000-0000-4000-a000-000000000011', 'c0000000-0000-4000-a000-000000000014', 1.75, NULL, true),
  ('a4000000-0000-4000-a000-000000000005', 'b0000000-0000-4000-a000-000000000002', 'c0000000-0000-4000-a000-000000000008', 4.00, 'Sin acuerdo firmado, quedó sin efecto', false)
ON CONFLICT (id) DO NOTHING;

-- ---------- Log de transferencias ----------
-- Se escribe directo: `obras_transferir()` exige sesión autenticada con el
-- permiso, y acá no hay sesión. La fila es el dato que la ficha muestra.
INSERT INTO obras_transferencias (id, obra_id, de_usuario_id, a_usuario_id, ejecutada_por, created_at) VALUES
  ('a5000000-0000-4000-a000-000000000001', 'b0000000-0000-4000-a000-000000000014', '015fa985-fe21-4434-b3c5-7ac78732d765', '48b90421-a639-4637-b361-501fa7e1a1a0', '015fa985-fe21-4434-b3c5-7ac78732d765', now() - interval '46 days'),
  ('a5000000-0000-4000-a000-000000000002', 'b0000000-0000-4000-a000-000000000013', '015fa985-fe21-4434-b3c5-7ac78732d765', '48b90421-a639-4637-b361-501fa7e1a1a0', '015fa985-fe21-4434-b3c5-7ac78732d765', now() - interval '12 days'),
  ('a5000000-0000-4000-a000-000000000003', 'b0000000-0000-4000-a000-000000000004', '48b90421-a639-4637-b361-501fa7e1a1a0', '015fa985-fe21-4434-b3c5-7ac78732d765', '015fa985-fe21-4434-b3c5-7ac78732d765', now() - interval '3 days')
ON CONFLICT (id) DO NOTHING;

-- ---------- Log de accesos a ficha de persona ----------
-- Lo escribe `obras_ficha_persona()` en la app. Sembrado a mano para que la
-- auditoría tenga qué mostrar: seis aperturas del mismo usuario en dos días
-- es exactamente la forma que tiene que ser visible.
INSERT INTO obras_accesos_persona (id, usuario_id, persona_id, created_at) VALUES
  ('a6000000-0000-4000-a000-000000000001', '015fa985-fe21-4434-b3c5-7ac78732d765', 'c0000000-0000-4000-a000-000000000002', now() - interval '9 days'),
  ('a6000000-0000-4000-a000-000000000002', '015fa985-fe21-4434-b3c5-7ac78732d765', 'c0000000-0000-4000-a000-000000000001', now() - interval '8 days'),
  ('a6000000-0000-4000-a000-000000000003', '015fa985-fe21-4434-b3c5-7ac78732d765', 'c0000000-0000-4000-a000-000000000002', now() - interval '5 days'),
  ('a6000000-0000-4000-a000-000000000004', '48b90421-a639-4637-b361-501fa7e1a1a0', 'c0000000-0000-4000-a000-000000000012', now() - interval '4 days'),
  ('a6000000-0000-4000-a000-000000000005', '48b90421-a639-4637-b361-501fa7e1a1a0', 'c0000000-0000-4000-a000-000000000014', now() - interval '2 days'),
  ('a6000000-0000-4000-a000-000000000006', '48b90421-a639-4637-b361-501fa7e1a1a0', 'c0000000-0000-4000-a000-000000000015', now() - interval '2 days'),
  ('a6000000-0000-4000-a000-000000000007', '015fa985-fe21-4434-b3c5-7ac78732d765', 'c0000000-0000-4000-a000-000000000009', now() - interval '1 day')
ON CONFLICT (id) DO NOTHING;
