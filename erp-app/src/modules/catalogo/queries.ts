import type { Moneda } from "@/lib/monedas";
import { createClient } from "@/lib/supabase/server";
import type {
  CasoCalculado,
  Caso,
  Categoria,
  Color,
  Contenido,
  Costo,
  FilaHistoria,
  FilaHistoriaVersion,
  Insumo,
  InsumoBasico,
  Oferta,
  Paquete,
  Porcentaje,
  PrecioReferencia,
  TipoCatalogo,
  TipoInsumo,
  Version,
  VersionResumen,
} from "./types";

export async function getCategorias(tipo: TipoCatalogo): Promise<Categoria[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("catalogo_categorias")
    .select("id, nombre, activo")
    .eq("tipo", tipo)
    .order("nombre");
  if (error) throw error;
  return data;
}

export async function getColores(): Promise<Color[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("catalogo_colores").select("id, nombre, activo").order("nombre");
  if (error) throw error;
  return data;
}

// Los costos los filtra la base: sin `catalogo_costos` (o `catalogo_fijos_editar` para un servicio),
// `catalogo_costos_vigentes` no trae ninguno.
export async function getInsumos(tipo: TipoInsumo): Promise<Insumo[]> {
  const supabase = await createClient();
  const [insumos, costos] = await Promise.all([
    supabase
      .from("catalogo_insumos")
      .select(
        "id, nombre, categoria_id, unidad, peso, espesor, con_color, activo, catalogo_variantes(id, color_id, activo)",
      )
      .eq("tipo", tipo)
      .order("nombre"),
    supabase.rpc("catalogo_costos_vigentes"),
  ]);
  if (insumos.error) throw insumos.error;
  if (costos.error) throw costos.error;

  const porVariante = new Map<string, Costo>(
    costos.data.map((c) => [c.variante_id, { costo: c.costo, moneda: c.moneda, desde: c.created_at }]),
  );
  return insumos.data.map(({ catalogo_variantes, ...i }) => ({
    ...i,
    variantes: catalogo_variantes.map((v) => ({ ...v, costo: porVariante.get(v.id) ?? null })),
  }));
}

export async function getMonedaPrincipal(): Promise<Moneda> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("monedas_principal_actual");
  if (error) throw error;
  return data;
}

export async function getPorcentajes(): Promise<Porcentaje[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_porcentajes_vigentes");
  if (error) throw error;
  return data
    .map(({ id, porcentaje_id, created_at, ...v }) => ({
      id: porcentaje_id,
      valor_id: id,
      desde: created_at,
      nombre: v.nombre,
      porcentaje: v.porcentaje,
      paso: v.paso,
      categorias: v.categorias,
      minimo: v.minimo,
      minimo_moneda: v.minimo_moneda,
      minimo_por: v.minimo_por,
      opcional: v.opcional,
      de_baja: v.de_baja,
    }))
    .sort((a, b) => a.paso - b.paso || a.nombre.localeCompare(b.nombre));
}

// Vacía sin la vista: la base lo filtra.
export async function getPorcentajeHistoria(id: string): Promise<FilaHistoria[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_porcentajes_historia", { p_id: id });
  if (error) throw error;
  return data as FilaHistoria[];
}

// ---------- Paquetes y versiones ----------

const SELECT_PAQUETE = `id, activo,
  baja_insumo:catalogo_insumos!catalogo_paquetes_baja_insumo_id_fkey(nombre),
  baja_variante:catalogo_variantes!catalogo_paquetes_baja_variante_id_fkey(catalogo_insumos(nombre), catalogo_colores(nombre)),
  catalogo_versiones(id, numero, estado, nombre, categoria_id)`;

type PaqueteFila = {
  id: string;
  activo: boolean;
  baja_insumo: { nombre: string } | null;
  baja_variante: { catalogo_insumos: { nombre: string } | null; catalogo_colores: { nombre: string } | null } | null;
  catalogo_versiones: VersionResumen[];
};

function aPaquete(p: PaqueteFila): Paquete {
  const v = p.baja_variante;
  return {
    id: p.id,
    activo: p.activo,
    baja_por: p.baja_insumo
      ? p.baja_insumo.nombre
      : v
        ? `${v.catalogo_insumos?.nombre ?? ""} · ${v.catalogo_colores?.nombre ?? ""}`
        : null,
    versiones: [...p.catalogo_versiones].sort((a, b) => b.numero - a.numero),
  };
}

export async function getPaquetes(): Promise<Paquete[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("catalogo_paquetes").select(SELECT_PAQUETE);
  if (error) throw error;
  return (data as unknown as PaqueteFila[]).map(aPaquete);
}

export async function getVersion(id: string): Promise<Version | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("catalogo_versiones")
    .select(
      `id, numero, estado, nombre, categoria_id,
       catalogo_paquetes(${SELECT_PAQUETE}),
       catalogo_versiones_colores(id, color_id, base, activo, catalogo_colores(nombre)),
       catalogo_versiones_historia(id, accion, motivo, activo, created_at, usuarios(nombre))`,
    )
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const fila = data as unknown as VersionResumen & {
    catalogo_paquetes: PaqueteFila;
    catalogo_versiones_colores: {
      id: string;
      color_id: string;
      base: boolean;
      activo: boolean;
      catalogo_colores: { nombre: string } | null;
    }[];
    catalogo_versiones_historia: {
      id: string;
      accion: FilaHistoriaVersion["accion"];
      motivo: string | null;
      activo: boolean;
      created_at: string;
      usuarios: { nombre: string } | null;
    }[];
  };
  return {
    id: fila.id,
    numero: fila.numero,
    estado: fila.estado,
    nombre: fila.nombre,
    categoria_id: fila.categoria_id,
    paquete: aPaquete(fila.catalogo_paquetes),
    colores: fila.catalogo_versiones_colores
      .filter((c) => c.activo)
      .map((c) => ({ id: c.id, color_id: c.color_id, base: c.base, nombre: c.catalogo_colores?.nombre ?? "" }))
      .sort((a, b) => Number(b.base) - Number(a.base) || a.nombre.localeCompare(b.nombre)),
    historia: fila.catalogo_versiones_historia
      .filter((h) => h.activo)
      .map((h) => ({
        id: h.id,
        accion: h.accion,
        motivo: h.motivo,
        quien: h.usuarios?.nombre ?? null,
        created_at: h.created_at,
      }))
      .sort((a, b) => b.created_at.localeCompare(a.created_at)),
  };
}

export async function getContenido(versionId: string): Promise<Contenido> {
  const supabase = await createClient();
  const [piezas, variables, materiales, opciones, condiciones, casos] = await Promise.all([
    supabase
      .from("catalogo_piezas")
      .select(
        "id, nombre, orden, cantidad, opcional, incluida, requiere_pieza_id, secundario, calcula_espesor, peso_a_produccion, espesor_a_produccion, activo",
      )
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden"),
    supabase
      .from("catalogo_variables")
      .select(
        "id, pieza_id, nombre, orden, ingresa_vendedor, es_lista, formula, valores, valor_predeterminado, es_cantidad, minimo, maximo, secundario, a_produccion, segun_material_id, activo",
      )
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden"),
    supabase
      .from("catalogo_materiales")
      .select(
        "id, pieza_id, orden, tipo, nombre, insumo_id, medida, ancho, alto, area, cantidad, eleccion, sin_eleccion, sigue_material_id, secundario, cuenta_peso, cuenta_espesor, activo",
      )
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden"),
    supabase
      .from("catalogo_opciones")
      .select(
        "id, material_id, orden, insumo_id, sigue_opcion_id, predeterminada, medida, ancho, alto, area, cantidad, activo",
      )
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden"),
    supabase
      .from("catalogo_condiciones")
      .select("id, variable_id, material_id, opcion_id, condicion, mensaje, bloquea, activo")
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("created_at"),
    supabase
      .from("catalogo_casos")
      .select("id, nombre, entrada")
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("created_at"),
  ]);
  for (const r of [piezas, variables, materiales, opciones, condiciones, casos]) if (r.error) throw r.error;
  return {
    piezas: piezas.data ?? [],
    variables: variables.data ?? [],
    materiales: materiales.data ?? [],
    opciones: opciones.data ?? [],
    condiciones: condiciones.data ?? [],
    casos: (casos.data ?? []) as Caso[],
  };
}

// Las tres son DEFINER con su propio control de permiso (CA016 sin la vista).
export async function getFrena(versionId: string): Promise<string[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_version_revisar", { p_version: versionId });
  if (error) throw error;
  return data ?? [];
}

export async function getOferta(versionId: string): Promise<Oferta[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_version_oferta", { p_version: versionId });
  if (error) throw error;
  return data as Oferta[];
}

export async function getCasosCalculados(versionId: string): Promise<CasoCalculado[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_casos_calcular", { p_version: versionId });
  if (error) throw error;
  return data as unknown as CasoCalculado[];
}

// Nombre, tipo y unidad de insumos y servicios fijos: se leen desde cualquier pestaña del catálogo.
export async function getInsumosBasicos(): Promise<InsumoBasico[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("catalogo_insumos")
    .select("id, nombre, tipo, unidad, categoria_id, con_color, activo")
    .order("nombre");
  if (error) throw error;
  return data as InsumoBasico[];
}

// Lo que más cambió primero. Pide `catalogo_aprobar` (42501 sin él).
export async function getPreciosReferencia(moneda: Moneda, dias: number): Promise<PrecioReferencia[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_precios_referencia", {
    p_moneda: moneda,
    p_desde: new Date(Date.now() - dias * 86_400_000).toISOString(),
  });
  if (error) throw error;
  return data;
}
