import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";
import type { IvaTotal, LineaDebajo, MensajeCatalogo } from "./types";

type Presupuesto = Database["public"]["Tables"]["presupuestos"]["Row"];
type Autorizacion = Database["public"]["Tables"]["presupuestos_autorizaciones"]["Row"];

export type PresupuestoResumen = Pick<Presupuesto, "id" | "codigo" | "nombre" | "estado"> & { obra: string };

// La RLS decide cuáles: los de las obras que quien llama ve o, con `presupuestos_administrar`, todos.
export async function getPresupuestos(): Promise<PresupuestoResumen[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos")
    .select("id, codigo, nombre, estado, obra:obras!inner(nombre)")
    .eq("activo", true)
    .order("numero", { ascending: false });
  if (error) throw error;
  return data.map(({ obra, ...p }) => ({ ...p, obra: obra.nombre }));
}

export type Pedido = Pick<Autorizacion, "id" | "tipo" | "estado" | "motivo" | "pedido_por" | "resuelto_por" | "resuelto_en" | "created_at"> & {
  texto: string;
  version: { id: string; numero: number; estado: Database["public"]["Enums"]["estado_version_presupuesto"] };
  presupuesto: Pick<Presupuesto, "id" | "codigo" | "nombre" | "obra_id">;
};

const PEDIDO = `id, tipo, estado, motivo, pedido, pedido_por, resuelto_por, resuelto_en, created_at,
  version:presupuestos_versiones!inner(id, numero, estado, activo,
    presupuesto:presupuestos!presupuestos_versiones_presupuesto_id_fkey!inner(id, codigo, nombre, obra_id, activo))`;

async function getPedidos(estadoVersion: Pedido["version"]["estado"]): Promise<Pedido[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos_autorizaciones")
    .select(PEDIDO)
    .eq("version.estado", estadoVersion)
    .eq("version.activo", true)
    .eq("version.presupuesto.activo", true)
    .order("created_at");
  if (error) throw error;
  return data.map(({ pedido, version: { presupuesto, ...version }, ...a }) => ({
    ...a,
    texto: (pedido as { texto: string }).texto.replace(/^autorización [^:]+: /, ""),
    version,
    presupuesto,
  }));
}

// Lo que espera a quien llama: los pedidos al jefe pendientes, de las obras donde puede autorizar.
export async function getEsperan(): Promise<Pedido[]> {
  const pendientes = (await getPedidos("en_revision")).filter((p) => p.tipo === "comercial" && p.estado === "pendiente");
  const supabase = await createClient();
  const obras = [...new Set(pendientes.map((p) => p.presupuesto.obra_id))];
  const puede = await Promise.all(
    obras.map(async (obra) => {
      const { data, error } = await supabase.rpc("presupuestos_puede_autorizar", { p_tipo: "comercial", p_obra: obra });
      if (error) throw error;
      return data;
    })
  );
  return pendientes.filter((p) => puede[obras.indexOf(p.presupuesto.obra_id)]);
}

// Las versiones que volvieron a borrador por una devolución y todavía no se pidieron de nuevo:
// pedir otra vez crea filas más nuevas, y retirar ese pedido no las vuelve a mostrar.
export async function getDevueltas(): Promise<Pedido[]> {
  const pedidos = await getPedidos("borrador");
  const ultima = new Map<string, string>();
  for (const p of pedidos) ultima.set(p.version.id, p.created_at);
  return pedidos.filter((p) => p.estado === "devuelta" && p.created_at === ultima.get(p.version.id));
}

// id de usuario → nombre, de lo que se ve en Obras: quien pide o devuelve trabaja la obra.
export async function getNombres(): Promise<Record<string, string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("obras_nombres");
  if (error) throw error;
  return Object.fromEntries(data.map((n) => [n.id, n.nombre]));
}

// Las obras activas que quien llama ve; armar en una de ellas lo decide `presupuestos_alta`.
export async function getObrasParaPresupuestar(): Promise<{ id: string; nombre: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("obras").select("id, nombre").eq("activo", true).order("nombre");
  if (error) throw error;
  return data;
}

type Version = Database["public"]["Tables"]["presupuestos_versiones"]["Row"];

export type FichaPresupuesto = Presupuesto & {
  obra: { id: string; nombre: string };
  versiones: Pick<Version, "id" | "numero" | "variante" | "variante_nombre" | "estado" | "vence" | "created_at">[];
};

export async function getPresupuesto(id: string): Promise<FichaPresupuesto | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos")
    .select(
      "*, obra:obras!inner(id, nombre), versiones:presupuestos_versiones!presupuestos_versiones_presupuesto_id_fkey(id, numero, variante, variante_nombre, estado, vence, created_at, activo)"
    )
    .eq("id", id)
    .eq("versiones.activo", true)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return { ...data, versiones: data.versiones.map(({ activo: _, ...v }) => v).sort((a, b) => b.numero - a.numero) };
}

type Tablas = Database["public"]["Tables"];
type Funciones = Database["public"]["Functions"];
type Importe = Omit<Funciones["presupuestos_version_importes"]["Returns"][number], "debajo" | "clave" | "importe" | "importe_con_iva"> & {
  clave: string | null;
  importe: number | null;
  importe_con_iva: number | null;
  debajo: LineaDebajo[] | null;
};
type Total = Omit<Funciones["presupuestos_version_totales"]["Returns"][number], "iva"> & { iva: IvaTotal[] };

export type VersionEditor = {
  presupuesto: Pick<Presupuesto, "id" | "codigo" | "nombre" | "estado" | "version_aprobada_id"> & { obra: { id: string; nombre: string } };
  version: Pick<Version, "id" | "numero" | "variante" | "variante_nombre" | "iva_discriminado" | "descuento" | "estado" | "vence" | "created_at">;
  secciones: Pick<Tablas["presupuestos_secciones"]["Row"], "id" | "nombre" | "moneda" | "alicuota">[];
  renglones: (Pick<
    Tablas["presupuestos_renglones"]["Row"],
    "id" | "seccion_id" | "tipo" | "designacion" | "ubicacion" | "cantidad" | "mensaje" | "mantener" | "condiciones_en"
  > & { mensajes: MensajeCatalogo[] })[];
  importes: Importe[];
  totales: Total[];
};

// Los importes y los totales los calcula la base, con el recargo y el redondeo: acá no se multiplica nada.
export async function getVersion(presupuestoId: string, versionId: string): Promise<VersionEditor | null> {
  const supabase = await createClient();
  const [version, secciones, renglones, importes, totales] = await Promise.all([
    supabase
      .from("presupuestos_versiones")
      .select(
        `id, numero, variante, variante_nombre, iva_discriminado, descuento, estado, vence, created_at,
         presupuesto:presupuestos!presupuestos_versiones_presupuesto_id_fkey!inner(id, codigo, nombre, estado, version_aprobada_id,
           obra:obras!inner(id, nombre))`
      )
      .eq("id", versionId)
      .eq("presupuesto_id", presupuestoId)
      .eq("activo", true)
      .maybeSingle(),
    supabase
      .from("presupuestos_secciones")
      .select("id, nombre, moneda, alicuota")
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden")
      .order("nombre"),
    supabase
      .from("presupuestos_renglones")
      .select("id, seccion_id, tipo, designacion, ubicacion, cantidad, mensaje, mensajes, mantener, condiciones_en")
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden")
      .order("created_at"),
    supabase.rpc("presupuestos_version_importes", { p_version: versionId }),
    supabase.rpc("presupuestos_version_totales", { p_version: versionId }),
  ]);
  for (const r of [version, secciones, renglones, importes, totales]) if (r.error) throw r.error;
  if (!version.data) return null;
  const { presupuesto, ...v } = version.data;
  return {
    presupuesto,
    version: v,
    secciones: secciones.data ?? [],
    renglones: (renglones.data ?? []).map((r) => ({ ...r, mensajes: (r.mensajes ?? []) as MensajeCatalogo[] })),
    importes: (importes.data ?? []).map((i) => ({ ...i, debajo: i.debajo as LineaDebajo[] | null })),
    totales: (totales.data ?? []).map((t) => ({ ...t, iva: t.iva as IvaTotal[] })),
  };
}
