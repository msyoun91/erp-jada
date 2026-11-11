"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import type { Database } from "@/lib/supabase/database.types";
import { createClient } from "@/lib/supabase/server";
import { idSchema } from "@/lib/validacion";
import { errorDeUpdate, mensajeError } from "@/lib/utils";
import {
  altaSchema,
  datosVersionSchema,
  devolverSchema,
  nombreSchema,
  opcionalesSchema,
  renglonCatalogoSchema,
  renglonManoSchema,
  seccionSchema,
  todasSeccionesSchema,
  type AltaForm,
  type DatosVersionForm,
  type DevolverForm,
  type FormularioVenta,
  type NombreForm,
  type OpcionalesForm,
  type RenglonCatalogoForm,
  type RenglonManoForm,
  type SeccionForm,
  type TodasSeccionesForm,
} from "./types";

// Quién arma y en qué estado se edita lo deciden la RLS y los triggers: acá solo se valida la forma y se traduce el error.

type Resultado = { success: true } | { success: false; error: string };

function trasGuardar(error: string | null): Resultado {
  if (error) return { success: false, error };
  revalidatePath("/presupuestos", "layout");
  return { success: true };
}

function invalido(issues: { message: string }[]) {
  return { success: false as const, error: issues[0].message };
}

function errorDeSeccion(error: { code?: string } | null): string | null {
  if (!error) return null;
  return error.code === "23505" ? "Ya hay una sección con ese nombre en esta versión" : mensajeError(error);
}

export async function crearPresupuesto(input: AltaForm) {
  const parsed = altaSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const d = parsed.data;
  const supabase = await createClient();
  const { data: id, error } = await supabase.rpc("presupuestos_alta", {
    p_obra: d.obra,
    p_nombre: d.nombre,
    p_moneda: d.moneda,
    p_alicuota: d.alicuota,
    ...(d.seccion ? { p_seccion: d.seccion } : {}),
  });
  if (error) return { success: false as const, error: mensajeError(error) };
  revalidatePath("/presupuestos", "layout");
  return { success: true as const, id };
}

// Aprobado o rechazado, el nombre no cambia (PR027).
export async function guardarNombre(input: NombreForm): Promise<Resultado> {
  const parsed = nombreSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  return trasGuardar(
    errorDeUpdate(
      await supabase.from("presupuestos").update({ nombre: parsed.data.nombre }, { count: "exact" }).eq("id", parsed.data.id)
    )
  );
}

// Corregir copia la publicada en la misma variante; sumar variante, en la siguiente. Otra abierta de esa variante: 23505.
export async function copiarVersion(desde: string, varianteNueva: boolean) {
  const parsed = z.object({ desde: idSchema, nueva: z.boolean() }).safeParse({ desde, nueva: varianteNueva });
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("presupuestos_version_copiar", {
    p_desde: parsed.data.desde,
    p_variante_nueva: parsed.data.nueva,
  });
  revalidatePath("/presupuestos", "layout");
  if (error) {
    return {
      success: false as const,
      error: error.code === "23505" ? "Esta variante ya tiene una versión abierta. Recargá la página." : mensajeError(error),
    };
  }
  return { success: true as const, id: data };
}

export async function quitarVariante(version: string): Promise<Resultado> {
  const parsed = idSchema.safeParse(version);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("presupuestos_variante_quitar", { p_version: parsed.data });
  return trasGuardar(error ? mensajeError(error) : null);
}

// Solo un borrador, y nunca la única versión activa (PR005, PR006).
export async function descartarVersion(id: string): Promise<Resultado> {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  return trasGuardar(
    errorDeUpdate(await supabase.from("presupuestos_versiones").update({ activo: false }, { count: "exact" }).eq("id", parsed.data))
  );
}

export async function guardarDatosVersion(input: DatosVersionForm): Promise<Resultado> {
  const parsed = datosVersionSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, variante_nombre, ...datos } = parsed.data;
  const supabase = await createClient();
  return trasGuardar(
    errorDeUpdate(
      await supabase
        .from("presupuestos_versiones")
        .update({ ...datos, variante_nombre: variante_nombre || null }, { count: "exact" })
        .eq("id", id)
    )
  );
}

export async function guardarSeccion(input: SeccionForm): Promise<Resultado> {
  const parsed = seccionSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, orden, ...datos } = parsed.data;
  const supabase = await createClient();
  if (id) {
    const r = await supabase.from("presupuestos_secciones").update(datos, { count: "exact" }).eq("id", id);
    return trasGuardar(r.error ? errorDeSeccion(r.error) : errorDeUpdate(r));
  }
  const { error } = await supabase.from("presupuestos_secciones").insert({ ...datos, version_id, orden });
  return trasGuardar(errorDeSeccion(error));
}

export async function sacarSeccion(id: string): Promise<Resultado> {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  return trasGuardar(
    errorDeUpdate(await supabase.from("presupuestos_secciones").update({ activo: false }, { count: "exact" }).eq("id", parsed.data))
  );
}

// El orden es el de la lista que llega: cada sección toma su posición. Son pocas, una a una.
export async function ordenarSecciones(versionId: string, ids: string[]): Promise<Resultado> {
  const parsed = z.object({ version: idSchema, ids: z.array(idSchema).min(1) }).safeParse({ version: versionId, ids });
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  for (const [orden, id] of parsed.data.ids.entries()) {
    const error = errorDeUpdate(
      await supabase
        .from("presupuestos_secciones")
        .update({ orden }, { count: "exact" })
        .eq("id", id)
        .eq("version_id", parsed.data.version)
    );
    if (error) return trasGuardar(error);
  }
  return trasGuardar(null);
}

// Un solo UPDATE por versión: "todas al 10,5 %" o "todas en pesos" (decisiones/presupuestos.md → *Secciones y opcionales*).
export async function cambiarTodasLasSecciones(input: TodasSeccionesForm): Promise<Resultado> {
  const parsed = todasSeccionesSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { version_id, moneda, alicuota } = parsed.data;
  const supabase = await createClient();
  return trasGuardar(
    errorDeUpdate(
      await supabase
        .from("presupuestos_secciones")
        .update({ ...(moneda !== "" ? { moneda } : {}), ...(alicuota !== "" ? { alicuota } : {}) }, { count: "exact" })
        .eq("version_id", version_id)
        .eq("activo", true)
    )
  );
}

// Lo que pregunta el paquete al cargarlo: NULL si ya no está a la venta.
export async function formularioVenta(paquete: string) {
  const parsed = idSchema.safeParse(paquete);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("catalogo_venta_formulario", { p_paquete: parsed.data });
  if (error) return { success: false as const, error: mensajeError(error) };
  return { success: true as const, formulario: data as FormularioVenta | null };
}

// La moneda la pone la base con la de la sección, y no cambia (PR009).
export async function guardarRenglonMano(input: RenglonManoForm): Promise<Resultado> {
  const parsed = renglonManoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, ...datos } = parsed.data;
  const supabase = await createClient();
  if (id) {
    return trasGuardar(
      errorDeUpdate(await supabase.from("presupuestos_renglones").update(datos, { count: "exact" }).eq("id", id))
    );
  }
  const { error } = await supabase.from("presupuestos_renglones").insert(nuevo({ ...datos, version_id, tipo: "mano" }));
  return trasGuardar(error ? mensajeError(error) : null);
}

type RenglonNuevo = Database["public"]["Tables"]["presupuestos_renglones"]["Insert"];

// `moneda` la pone el trigger con la de la sección, y no tiene GRANT: el tipo generado la pide porque no tiene default.
function nuevo(r: Omit<RenglonNuevo, "moneda">) {
  return r as RenglonNuevo;
}

// El precio lo pone la base al guardar (no hay un "calcular" aparte): se devuelve cómo quedó, para avisar si no dio número.
export async function guardarRenglonCatalogo(input: RenglonCatalogoForm) {
  const parsed = renglonCatalogoSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { id, version_id, entrada, opcionales, ...datos } = parsed.data;
  const cargado = entrada && opcionales ? { entrada, opcionales } : {};
  const supabase = await createClient();
  const { data, error } = id
    ? await supabase.from("presupuestos_renglones").update({ ...datos, ...cargado }).eq("id", id).select("precio, mensaje")
    : await supabase
        .from("presupuestos_renglones")
        .insert(nuevo({ ...datos, ...cargado, version_id, tipo: "catalogo" }))
        .select("precio, mensaje");
  const falla = errorDeUpdate({ error, count: data?.length ?? 0 });
  if (falla || !data) return { success: false as const, error: falla ?? "" };
  revalidatePath("/presupuestos", "layout");
  return { success: true as const, precio: data[0].precio, mensaje: data[0].mensaje };
}

// Sin fila, el opcional va en el precio; volver al precio desactiva la fila, que no vuelve (PR002): pasarlo otra vez a
// debajo o aparte crea otra. Uno por uno, solo los que cambiaron; cada cambio toca las ventanas que lo tienen.
export async function guardarOpcionales(input: OpcionalesForm): Promise<Resultado> {
  const parsed = opcionalesSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const { version_id, opcionales } = parsed.data;
  const supabase = await createClient();
  const tabla = () => supabase.from("presupuestos_opcionales");
  for (const o of opcionales.filter((o) => o.como !== o.inicial)) {
    const forma = o.como === "debajo" ? ("debajo" as const) : ("aparte" as const);
    const seccion_id = o.como === "debajo" ? null : o.como;
    const error = !o.fila
      ? errorDeUpdate({
          ...(await tabla().insert({ version_id, pieza: o.pieza, porcentaje_id: o.porcentaje_id, forma, seccion_id })),
          count: 1,
        })
      : errorDeUpdate(
          await tabla()
            .update(o.como === "precio" ? { activo: false } : { forma, seccion_id }, { count: "exact" })
            .eq("id", o.fila)
        );
    if (error) return trasGuardar(error);
  }
  return trasGuardar(null);
}

// Pedir, publicar y retirar los frena la base (PR005, PR014, PR017). Se revalida también al fallar: lo que frenó puede ser
// algo que cambió desde que se abrió la página, y la lista de *Antes de publicar* tiene que mostrarlo.
async function cicloVersion(
  rpc: "presupuestos_version_pedir" | "presupuestos_version_publicar" | "presupuestos_version_retirar",
  version: string
) {
  const parsed = idSchema.safeParse(version);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(rpc, { p_version: parsed.data });
  revalidatePath("/presupuestos", "layout");
  if (error) return { success: false as const, error: mensajeError(error) };
  return { success: true as const, estado: data };
}

// Devuelve el estado en que quedó: `publicado` si quien pide ya podía autorizar todo.
export async function pedirAutorizacion(version: string) {
  return cicloVersion("presupuestos_version_pedir", version);
}

export async function publicarVersion(version: string) {
  return cicloVersion("presupuestos_version_publicar", version);
}

export async function retirarVersion(version: string) {
  return cicloVersion("presupuestos_version_retirar", version);
}

export async function autorizarPedido(id: string): Promise<Resultado> {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("presupuestos_pedido_resolver", { p_id: parsed.data, p_autoriza: true });
  return trasGuardar(error ? mensajeError(error) : null);
}

export async function devolverPedido(input: DevolverForm): Promise<Resultado> {
  const parsed = devolverSchema.safeParse(input);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { error } = await supabase.rpc("presupuestos_pedido_resolver", {
    p_id: parsed.data.id,
    p_autoriza: false,
    p_motivo: parsed.data.motivo,
  });
  return trasGuardar(error ? mensajeError(error) : null);
}

// Mantener o pasar a hoy, una ventana o un mínimo, o varios de una vez. Escribir `mantener` recalcula aunque no cambie: a hoy
// también actualiza lo que ya estaba a hoy y cambió de precio (`presupuestos_renglones_a_hoy`). Mantener solo lo copiado, con
// su paquete: lo frena la base (PR013). Devuelve cómo quedó cada uno, para avisar lo que quedó sin precio.
export async function mantenerRenglones(version: string, ids: string[], mantener: boolean) {
  const parsed = z
    .object({ version: idSchema, ids: z.array(idSchema).min(1), mantener: z.boolean() })
    .safeParse({ version, ids, mantener });
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("presupuestos_renglones")
    .update({ mantener: parsed.data.mantener })
    .eq("version_id", parsed.data.version)
    .in("id", parsed.data.ids)
    .select("precio, mensaje");
  const falla = errorDeUpdate({ error, count: data?.length ?? 0 });
  if (falla || !data) return { success: false as const, error: falla ?? "" };
  revalidatePath("/presupuestos", "layout");
  return { success: true as const, renglones: data };
}

// Un mínimo lo saca la base (PR012): de acá solo se saca una ventana o uno a mano.
export async function sacarRenglon(id: string): Promise<Resultado> {
  const parsed = idSchema.safeParse(id);
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  return trasGuardar(
    errorDeUpdate(await supabase.from("presupuestos_renglones").update({ activo: false }, { count: "exact" }).eq("id", parsed.data))
  );
}

// De un mínimo, quien arma solo elige la sección.
export async function moverRenglon(id: string, seccion: string): Promise<Resultado> {
  const parsed = z.object({ id: idSchema, seccion: idSchema }).safeParse({ id, seccion });
  if (!parsed.success) return invalido(parsed.error.issues);
  const supabase = await createClient();
  return trasGuardar(
    errorDeUpdate(
      await supabase
        .from("presupuestos_renglones")
        .update({ seccion_id: parsed.data.seccion }, { count: "exact" })
        .eq("id", parsed.data.id)
    )
  );
}
