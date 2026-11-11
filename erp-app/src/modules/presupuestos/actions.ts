"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { idSchema } from "@/lib/validacion";
import { errorDeUpdate, mensajeError } from "@/lib/utils";
import {
  altaSchema,
  datosVersionSchema,
  seccionSchema,
  todasSeccionesSchema,
  type AltaForm,
  type DatosVersionForm,
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
