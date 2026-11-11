import type { Entrada } from "@/lib/entrada";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";
import { hoyISO } from "@/lib/utils";
import {
  estaVencida,
  opcionalesDe,
  textoCargado,
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

// La sección de la ficha de la obra: sus presupuestos, el más nuevo primero, y si quien mira arma ahí.
export async function getPresupuestosDeObra(obra: string) {
  const supabase = await createClient();
  const [lista, arma] = await Promise.all([
    supabase
      .from("presupuestos")
      .select("id, codigo, nombre, estado")
      .eq("obra_id", obra)
      .eq("activo", true)
      .order("numero", { ascending: false }),
    supabase.rpc("presupuestos_arma", { p_obra: obra }),
  ]);
  if (lista.error) throw lista.error;
  if (arma.error) throw arma.error;
  return { presupuestos: lista.data, arma: arma.data };
}

// Obra contratada → cuántos presupuestos publicados tiene: "Contratada · 1 en cotización" en la lista de Obras
// (decisiones/obras.md → *Los estados son solo comerciales*). Solo cuentan los publicados, como para mover la obra.
export async function getEnCotizacionDeContratadas(): Promise<Record<string, number>> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos")
    .select("obra_id, obra:obras!inner(estado)")
    .eq("estado", "publicado")
    .eq("activo", true)
    .eq("obra.estado", "contratada");
  if (error) throw error;
  const cuenta: Record<string, number> = {};
  for (const p of data) cuenta[p.obra_id] = (cuenta[p.obra_id] ?? 0) + 1;
  return cuenta;
}

export type Configuracion = Pick<
  Database["public"]["Tables"]["presupuestos_configuracion"]["Row"],
  "id" | "tope_descuento" | "plazo_dias" | "activo" | "created_at"
> & { quien: string | null };

// La vigente y el historial, lo más nuevo primero. `usuarios` no deja ver otros equipos: el nombre sale de quienes hoy
// tienen la vista, y el de quien ya no la tiene, "—".
export async function getConfiguraciones(): Promise<Configuracion[]> {
  const supabase = await createClient();
  const [filas, usuarios] = await Promise.all([
    supabase
      .from("presupuestos_configuracion")
      .select("id, tope_descuento, plazo_dias, activo, creado_por, created_at")
      .order("created_at", { ascending: false }),
    supabase.rpc("usuarios_con_permiso", { p_codigo: "presupuestos_configuracion" }),
  ]);
  if (filas.error) throw filas.error;
  if (usuarios.error) throw usuarios.error;
  const nombres = new Map(usuarios.data.map((u) => [u.id, u.nombre]));
  return filas.data.map(({ creado_por, ...c }) => ({ ...c, quien: nombres.get(creado_por) ?? null }));
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

// Lo que está a la venta, por categoría y nombre: para la calculadora de venta.
export async function getPaquetesVenta(): Promise<Funciones["catalogo_venta"]["Returns"]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_venta");
  if (error) throw error;
  return data;
}

type Version = Database["public"]["Tables"]["presupuestos_versiones"]["Row"];

export type FichaPresupuesto = Presupuesto & {
  obra: { id: string; nombre: string };
  versiones: Pick<Version, "id" | "numero" | "variante" | "variante_nombre" | "estado" | "vence" | "created_at">[];
  // Quien mira arma en la obra y el presupuesto admite cambios (activo, en borrador o publicado); lo frenan igual la RLS y
  // las funciones.
  arma: boolean;
  // Aprobado o rechazado, quien mira autoriza lo comercial en la obra: revierte (*Quién accede*).
  revierte: boolean;
  // De cada publicada vencida, cuándo se calculó el precio más viejo de sus renglones (mantenido, el del origen): el aviso
  // al aprobar. Solo para quien arma.
  precios_del: Record<string, string>;
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
  const versiones = data.versiones.map(({ activo: _, ...v }) => v).sort((a, b) => b.numero - a.numero);
  let arma = false;
  let revierte = false;
  const precios_del: Record<string, string> = {};
  if (data.activo && (data.estado === "borrador" || data.estado === "publicado")) {
    const r = await supabase.rpc("presupuestos_arma", { p_obra: data.obra.id });
    if (r.error) throw r.error;
    arma = r.data;
  } else if (data.estado === "aprobado" || data.estado === "rechazado") {
    const r = await supabase.rpc("presupuestos_puede_autorizar", { p_obra: data.obra.id, p_tipo: "comercial" });
    if (r.error) throw r.error;
    revierte = r.data;
  }
  const hoy = hoyISO();
  const vencidas = versiones.filter((v) => estaVencida(v, hoy)).map((v) => v.id);
  if (arma && data.estado === "publicado" && vencidas.length > 0) {
    const r = await supabase
      .from("presupuestos_renglones")
      .select("version_id, condiciones_en")
      .in("version_id", vencidas)
      .eq("activo", true)
      .not("condiciones_en", "is", null)
      .order("condiciones_en");
    if (r.error) throw r.error;
    for (const x of r.data) if (x.condiciones_en) precios_del[x.version_id] ??= x.condiciones_en;
  }
  return { ...data, versiones, arma, revierte, precios_del };
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
  presupuesto: Pick<Presupuesto, "id" | "codigo" | "nombre" | "estado" | "version_aprobada_id"> & {
    obra: Pick<Database["public"]["Tables"]["obras"]["Row"], "id" | "nombre" | "estado" | "motivo_perdida">;
  };
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
    | "catalogo_version_id"
    | "porcentaje_id"
    | "descripcion"
    | "precio"
    | "moneda"
  > & {
    mensajes: MensajeCatalogo[];
    entrada: Entrada | null;
    opcionales: string[];
    // La fecha de los precios con que se recalcula al mantener: la del origen. NULL si no se puede mantener (sin origen, a
    // mano, o una ventana con otro paquete que su origen: PR013).
    mantener_en: string | null;
  })[];
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
           obra:obras!inner(id, nombre, estado, motivo_perdida))`
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
        "id, seccion_id, tipo, designacion, ubicacion, cantidad, mensaje, mensajes, mantener, condiciones_en, paquete_id, catalogo_version_id, porcentaje_id, entrada, opcionales, descripcion, precio, moneda, origen:origen_id(paquete_id, condiciones_en)"
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
    renglones: (renglones.data ?? []).map(({ origen, ...r }) => ({
      ...r,
      mensajes: (r.mensajes ?? []) as MensajeCatalogo[],
      entrada: r.entrada as Entrada | null,
      opcionales: r.opcionales ?? [],
      mantener_en:
        origen && r.tipo !== "mano" && (r.tipo === "minimo" || origen.paquete_id === r.paquete_id) ? origen.condiciones_en : null,
    })),
    importes: (importes.data ?? []).map((i) => ({ ...i, debajo: i.debajo as LineaDebajo[] | null })),
    totales: (totales.data ?? []).map((t) => ({ ...t, iva: t.iva as IvaTotal[] })),
    paquetes,
    formularios,
    opcionales: [...opcionales.values()].sort((a, b) => a.nombre.localeCompare(b.nombre, "es")),
    antes,
  };
}

export type Impreso = {
  presupuesto: Pick<Presupuesto, "id" | "codigo" | "nombre" | "estado"> & {
    obra: { id: string; nombre: string; direccion: string; localidad: string | null };
  };
  // Cada versión, con lo cargado en sus ventanas por id de renglón: "ancho 1200 · alto 1500 · Negro · Vidrio: DVH 4/9/4".
  versiones: (VersionEditor & { cargado: Record<string, string | null> })[];
};

// Lo que se imprime (decisiones/presupuestos.md → *Pantallas*, *El impreso*): publicado y rechazado, la publicada de cada
// variante (rechazar no las toca); aprobado, la aprobada; un borrador, nada. Los nombres de lo cargado los da la base: quien
// ve el presupuesto no lee Catálogo. Lo que va debajo o aparte ya sale en su línea: no se repite en lo cargado.
export async function getImpreso(id: string): Promise<Impreso | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos")
    .select(
      "id, codigo, nombre, estado, version_aprobada_id, obra:obras!inner(id, nombre, direccion, localidad), versiones:presupuestos_versiones!presupuestos_versiones_presupuesto_id_fkey(id, variante, estado, activo)"
    )
    .eq("id", id)
    .eq("versiones.activo", true)
    .eq("versiones.estado", "publicado")
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const { version_aprobada_id, versiones: publicadas, ...presupuesto } = data;
  const ids =
    presupuesto.estado === "aprobado" && version_aprobada_id
      ? [version_aprobada_id]
      : presupuesto.estado === "borrador"
        ? []
        : publicadas.sort((a, b) => a.variante - b.variante).map((v) => v.id);
  const versiones = await Promise.all(
    ids.map(async (v) => {
      const [datos, r] = await Promise.all([getVersion(id, v), supabase.rpc("presupuestos_version_nombres", { p_version: v })]);
      if (r.error) throw r.error;
      if (!datos) return [];
      const { nombres, orden } = r.data as { nombres: Record<string, string>; orden: Record<string, number> };
      const mapa = new Map(Object.entries(nombres));
      const aparte = new Set(datos.opcionales.filter((o) => o.como !== "precio" && o.pieza).map((o) => o.clave));
      const cargado: Record<string, string | null> = {};
      for (const x of datos.renglones) {
        if (!x.entrada) continue;
        const piezas = Object.entries(x.entrada.piezas ?? {}).filter(([p]) => !aparte.has(`pieza:${p.trim().toLowerCase()}`));
        cargado[x.id] = textoCargado({ ...x.entrada, piezas: Object.fromEntries(piezas) }, mapa, (n) => orden[`${x.catalogo_version_id}:${n}`]);
      }
      return [{ ...datos, cargado }];
    })
  );
  return { presupuesto, versiones: versiones.flat() };
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

type PendienteTecnica = Funciones["presupuestos_revision_pendientes"]["Returns"][number];

export type RevisionPendiente = Pick<PendienteTecnica, "version_id" | "codigo" | "version" | "pedido_por_nombre" | "pedido_en"> & {
  ventanas: { pedido_id: string; etiqueta: string; motivos: string[] }[];
};

// Revisión técnica: una fila por versión, con sus ventanas (decisiones/presupuestos.md → *Pantallas*). Lo pendiente de una
// versión es de un solo pedido: pedir de nuevo pasa antes por borrador, que retira lo pendiente.
export async function getRevisionPendientes(): Promise<RevisionPendiente[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("presupuestos_revision_pendientes");
  if (error) throw error;
  const versiones = new Map<string, RevisionPendiente>();
  for (const { pedido_id, etiqueta, motivos, pedido_por: _, ...v } of data) {
    const fila = versiones.get(v.version_id) ?? { ...v, ventanas: [] };
    fila.ventanas.push({ pedido_id, etiqueta, motivos: motivos as string[] });
    versiones.set(v.version_id, fila);
  }
  return [...versiones.values()];
}

type RenglonTecnica = Funciones["presupuestos_revision_version"]["Returns"][number];

export type RevisionVersion = {
  codigo: string;
  version: number;
  renglones: (Omit<RenglonTecnica, "codigo" | "version" | "entrada" | "mensajes" | "motivos"> & {
    entrada: Entrada | null;
    mensajes: MensajeCatalogo[];
    motivos: string[];
    cargado: string | null;
  })[];
};

// Lo que lee Técnica, sin precios ni obra. El color y lo elegido van por id en la entrada: sus nombres salen de Catálogo, que
// se lee con cualquiera de sus vistas; sin ella, lo cargado queda en medidas y piezas.
export async function getRevisionVersion(versionId: string): Promise<RevisionVersion | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("presupuestos_revision_version", { p_version: versionId });
  if (error?.code === "42501") return null;
  if (error) throw error;
  if (data.length === 0) return null;
  const entradas = data.map((r) => r.entrada as Entrada | null);
  const colores = [...new Set(entradas.flatMap((e) => (e?.color ? [e.color] : [])))];
  const insumos = [
    ...new Set(entradas.flatMap((e) => Object.values(e?.elecciones ?? {}).flatMap((m) => Object.values(m).flatMap((i) => (i ? [i] : []))))),
  ];
  const versiones = [...new Set(data.flatMap((r) => (r.catalogo_version_id ? [r.catalogo_version_id] : [])))];
  const [c, i, v] = await Promise.all([
    colores.length > 0 ? supabase.from("catalogo_colores").select("id, nombre").in("id", colores) : null,
    insumos.length > 0 ? supabase.from("catalogo_insumos").select("id, nombre").in("id", insumos) : null,
    versiones.length > 0 ? supabase.from("catalogo_variables").select("version_id, nombre, orden").in("version_id", versiones) : null,
  ]);
  for (const r of [c, i, v]) if (r?.error) throw r.error;
  const nombres = new Map([...(c?.data ?? []), ...(i?.data ?? [])].map((x) => [x.id, x.nombre]));
  const orden = new Map((v?.data ?? []).map((x) => [`${x.version_id}:${x.nombre}`, x.orden]));
  return {
    codigo: data[0].codigo,
    version: data[0].version,
    renglones: data.map(({ codigo: _, version: __, ...r }, n) => ({
      ...r,
      entrada: entradas[n],
      mensajes: (r.mensajes ?? []) as MensajeCatalogo[],
      motivos: (r.motivos ?? []) as string[],
      cargado: entradas[n] ? textoCargado(entradas[n], nombres, (x) => orden.get(`${r.catalogo_version_id}:${x}`)) : null,
    })),
  };
}
