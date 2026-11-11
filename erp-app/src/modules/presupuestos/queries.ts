import type { Entrada } from "@/lib/entrada";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";
import {
  opcionalesDe,
  type AutorizacionVersion,
  type FormularioVenta,
  type IvaTotal,
  type LineaDebajo,
  type MensajeCatalogo,
  type Opcional,
  type OpcionalesForm,
  type PedidoComercial,
  type PedidoTecnica,
} from "./types";

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
  // Se edita en borrador, si quien mira arma en la obra; lo frenan igual la RLS y los triggers.
  editable: boolean;
  // Hasta acá el descuento no pide autorización; null, sin configuración.
  tope: number | null;
  secciones: Pick<Tablas["presupuestos_secciones"]["Row"], "id" | "nombre" | "moneda" | "alicuota" | "orden">[];
  renglones: (Pick<
    Tablas["presupuestos_renglones"]["Row"],
    | "id"
    | "seccion_id"
    | "tipo"
    | "designacion"
    | "ubicacion"
    | "cantidad"
    | "mensaje"
    | "mantener"
    | "condiciones_en"
    | "paquete_id"
    | "descripcion"
    | "precio"
    | "moneda"
  > & { mensajes: MensajeCatalogo[]; entrada: Entrada | null; opcionales: string[] })[];
  importes: Importe[];
  totales: Total[];
  // Para elegir el paquete de una ventana: solo si es editable.
  paquetes: Funciones["catalogo_venta"]["Returns"];
  // El formulario del paquete de cada ventana, por paquete; NULL si salió de la venta. Solo si es editable.
  formularios: Record<string, FormularioVenta | null>;
  // Cada opcional de las ventanas y cómo se ve; también los que tienen fila sin estar ya en ninguna ventana, que
  // frenan sacar la sección de su renglón aparte (PR011).
  opcionales: OpcionalVersion[];
  // En borrador, solo para quien arma; en revisión, para quien la ve. NULL en los demás casos.
  antes: AntesDePublicar | null;
};

export type AntesDePublicar = {
  // Quien mira arma en la obra: pide, publica y retira.
  arma: boolean;
  // Lo que frena pedir y publicar (`presupuestos_version_revisar`); vacío si no arma.
  frena: string[];
  autorizaciones: AutorizacionVersion[];
  // Los tipos de autorización pendientes que quien mira puede resolver.
  resuelve: AutorizacionVersion["tipo"][];
  // En borrador, la devolución que la trajo de vuelta, si el último pedido terminó así.
  devuelta: Pick<Autorizacion, "motivo" | "resuelto_por" | "resuelto_en"> | null;
  // Días hasta el vencimiento, si se publica hoy; NULL sin configuración.
  plazo: number | null;
};

export type OpcionalVersion = Pick<Opcional, "clave" | "nombre"> & {
  // La de `presupuestos_opcionales`; sin fila, va en el precio.
  fila: string | null;
  pieza: string | null;
  porcentaje_id: string | null;
  como: OpcionalesForm["opcionales"][number]["como"];
};

// Los importes y los totales los calcula la base, con el recargo y el redondeo: acá no se multiplica nada.
export async function getVersion(presupuestoId: string, versionId: string): Promise<VersionEditor | null> {
  const supabase = await createClient();
  const [version, secciones, renglones, importes, totales, configuracion, filas] = await Promise.all([
    supabase
      .from("presupuestos_versiones")
      .select(
        `id, numero, variante, variante_nombre, iva_discriminado, descuento, estado, vence, created_at,
         presupuesto:presupuestos!presupuestos_versiones_presupuesto_id_fkey!inner(id, codigo, nombre, estado, version_aprobada_id, activo,
           obra:obras!inner(id, nombre))`
      )
      .eq("id", versionId)
      .eq("presupuesto_id", presupuestoId)
      .eq("activo", true)
      .maybeSingle(),
    supabase
      .from("presupuestos_secciones")
      .select("id, nombre, moneda, alicuota, orden")
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden")
      .order("nombre"),
    supabase
      .from("presupuestos_renglones")
      .select(
        "id, seccion_id, tipo, designacion, ubicacion, cantidad, mensaje, mensajes, mantener, condiciones_en, paquete_id, entrada, opcionales, descripcion, precio, moneda"
      )
      .eq("version_id", versionId)
      .eq("activo", true)
      .order("orden")
      .order("created_at"),
    supabase.rpc("presupuestos_version_importes", { p_version: versionId }),
    supabase.rpc("presupuestos_version_totales", { p_version: versionId }),
    supabase.from("presupuestos_configuracion").select("tope_descuento, plazo_dias").eq("activo", true).maybeSingle(),
    supabase
      .from("presupuestos_opcionales")
      .select("id, pieza, porcentaje_id, clave, forma, seccion_id")
      .eq("version_id", versionId)
      .eq("activo", true),
  ]);
  for (const r of [version, secciones, renglones, importes, totales, configuracion, filas]) if (r.error) throw r.error;
  if (!version.data) return null;
  const { presupuesto: { activo, ...presupuesto }, ...v } = version.data;
  const abierta = activo && (v.estado === "borrador" || v.estado === "en_revision");
  let arma = false;
  if (abierta) {
    const { data, error } = await supabase.rpc("presupuestos_arma", { p_obra: presupuesto.obra.id });
    if (error) throw error;
    arma = data;
  }
  const editable = arma && v.estado === "borrador";
  const antes =
    abierta && (arma || v.estado === "en_revision")
      ? await getAntes(versionId, v.estado, presupuesto.obra.id, arma, configuracion.data?.plazo_dias ?? null)
      : null;
  let paquetes: VersionEditor["paquetes"] = [];
  const formularios: VersionEditor["formularios"] = {};
  if (editable) {
    const ids = [...new Set((renglones.data ?? []).flatMap((r) => (r.tipo === "catalogo" && r.paquete_id ? [r.paquete_id] : [])))];
    const [venta, ...forms] = await Promise.all([
      supabase.rpc("catalogo_venta"),
      ...ids.map((p) => supabase.rpc("catalogo_venta_formulario", { p_paquete: p })),
    ]);
    if (venta.error) throw venta.error;
    paquetes = venta.data;
    for (const [n, f] of forms.entries()) {
      if (f.error) throw f.error;
      formularios[ids[n]] = f.data as FormularioVenta | null;
    }
  }
  const opcionales = new Map<string, OpcionalVersion>();
  for (const f of Object.values(formularios)) {
    for (const o of f ? opcionalesDe(f) : []) {
      opcionales.set(o.clave, {
        clave: o.clave,
        nombre: o.nombre,
        fila: null,
        pieza: o.tipo === "pieza" ? o.nombre : null,
        porcentaje_id: o.tipo === "servicio" ? o.id : null,
        como: "precio",
      });
    }
  }
  for (const f of filas.data ?? []) {
    const clave = f.clave ?? "";
    opcionales.set(clave, {
      clave,
      nombre: opcionales.get(clave)?.nombre ?? f.pieza ?? "Un servicio que ya no está en ninguna ventana",
      fila: f.id,
      pieza: f.pieza,
      porcentaje_id: f.porcentaje_id,
      como: f.forma === "debajo" ? "debajo" : (f.seccion_id ?? ""),
    });
  }
  return {
    presupuesto,
    version: v,
    editable,
    tope: configuracion.data?.tope_descuento ?? null,
    secciones: secciones.data ?? [],
    renglones: (renglones.data ?? []).map((r) => ({
      ...r,
      mensajes: (r.mensajes ?? []) as MensajeCatalogo[],
      entrada: r.entrada as Entrada | null,
      opcionales: r.opcionales ?? [],
    })),
    importes: (importes.data ?? []).map((i) => ({ ...i, debajo: i.debajo as LineaDebajo[] | null })),
    totales: (totales.data ?? []).map((t) => ({ ...t, iva: t.iva as IvaTotal[] })),
    paquetes,
    formularios,
    opcionales: [...opcionales.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, "es")),
    antes,
  };
}

// En borrador, lo que se va a pedir sale de `presupuestos_version_pedido`, que calcula a hoy; en revisión, de las filas del
// último pedido, con lo que se pidió guardado: quien autoriza ve lo que se pidió. Las filas de un mismo pedido comparten
// `created_at` (el `now()` de su transacción).
async function getAntes(
  versionId: string,
  estado: Version["estado"],
  obra: string,
  arma: boolean,
  plazo: number | null
): Promise<AntesDePublicar> {
  const supabase = await createClient();
  const borrador = estado === "borrador";
  const [filas, revisar, pedido] = await Promise.all([
    supabase
      .from("presupuestos_autorizaciones")
      .select("id, tipo, estado, motivo, pedido, pedido_por, resuelto_por, resuelto_en, created_at")
      .eq("version_id", versionId)
      .order("created_at", { ascending: false })
      .order("tipo"),
    arma ? supabase.rpc("presupuestos_version_revisar", { p_version: versionId }) : null,
    arma && borrador ? supabase.rpc("presupuestos_version_pedido", { p_version: versionId }) : null,
  ]);
  for (const r of [filas, revisar, pedido]) if (r?.error) throw r.error;
  const vuelta = (filas.data ?? []).filter((f, _, todas) => f.created_at === todas[0].created_at);

  let autorizaciones: AutorizacionVersion[];
  if (borrador) {
    const p = pedido?.data as { comercial: PedidoComercial | null; tecnica: (PedidoTecnica & { estado: "autorizada" | null })[] } | undefined;
    const sinFila = { id: null, pedido_por: null, pedido_en: null, resuelto_por: null, resuelto_en: null };
    autorizaciones = [
      ...(p?.comercial ? [{ ...sinFila, tipo: "comercial" as const, estado: null, pedido: p.comercial }] : []),
      ...(p?.tecnica ?? []).map((t) => ({ ...sinFila, tipo: "tecnica" as const, estado: t.estado, pedido: t })),
    ];
  } else {
    autorizaciones = vuelta.flatMap((f): AutorizacionVersion[] => {
      if (f.estado !== "pendiente" && f.estado !== "autorizada") return [];
      const comun = { id: f.id, estado: f.estado, pedido_por: f.pedido_por, pedido_en: f.created_at, resuelto_por: f.resuelto_por, resuelto_en: f.resuelto_en };
      return [
        f.tipo === "comercial"
          ? { ...comun, tipo: "comercial", pedido: f.pedido as PedidoComercial }
          : { ...comun, tipo: "tecnica", pedido: f.pedido as PedidoTecnica },
      ];
    });
  }

  const pendientes = [...new Set(autorizaciones.filter((a) => a.estado === "pendiente").map((a) => a.tipo))];
  const puede = await Promise.all(
    pendientes.map(async (tipo) => {
      const { data, error } = await supabase.rpc("presupuestos_puede_autorizar", { p_tipo: tipo, p_obra: obra });
      if (error) throw error;
      return data;
    })
  );
  const devuelta = borrador ? vuelta.find((f) => f.estado === "devuelta") : undefined;
  return {
    arma,
    frena: revisar?.data ?? [],
    autorizaciones,
    resuelve: pendientes.filter((_, n) => puede[n]),
    devuelta: devuelta ? { motivo: devuelta.motivo, resuelto_por: devuelta.resuelto_por, resuelto_en: devuelta.resuelto_en } : null,
    plazo,
  };
}
