import { Fragment } from "react";
import { notFound } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { puedeAdministrar, puedePedir, puedeVerEquipo, puedeVerPlantillas, puedeVerTareas } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getHilo, getPlantillas } from "@/modules/tareas/queries";
import { REFERENCIA } from "@/modules/tareas/derivados";
import { HiloView } from "@/modules/tareas/components/HiloView";
import type { Pestana } from "@/modules/tareas/components/PasoPanel";
import { accionDe, ficha } from "../../fichas";

export default async function HiloPage(props: PageProps<"/tareas/[id]">) {
  const { id } = await props.params;
  const params = await props.searchParams;
  const { paso } = params;
  if (!(await puedeVerTareas()) || !idSchema.safeParse(id).success) notFound();

  const [datos, contexto, asignables, admin, pedir, delegador, plantillas] = await Promise.all([
    getHilo(id),
    getContexto(),
    getAsignables(),
    puedeAdministrar(),
    puedePedir(),
    puedeVerEquipo(),
    puedeVerPlantillas().then((ver) => (ver ? getPlantillas() : [])),
  ]);
  if (!datos) notFound();
  const { registro_ente, registro_id } = datos.hilo;
  const registro = registro_ente && registro_id ? await ficha(registro_ente, registro_id) : null;

  // Las pestañas del paso abierto: el registro del hilo primero, después lo que
  // menciona su descripción y quien lee puede abrir, sin repetir (registro.md).
  const abierto = datos.pasos.find((p) => p.id === paso);
  const pestanas: Pestana[] = [];
  if (abierto) {
    // El link de acción (`?vincular=`, `?estado=`) abre su panel en la pestaña del
    // registro; la key la vuelve a montar para que lo tome.
    const accion = accionDe(params);
    const conAccion = accion.vincular !== null || accion.estado !== null;
    const tab = conAccion && registro_ente && registro_id ? await ficha(registro_ente, registro_id, accion) : registro;
    if (tab && datos.sobre)
      pestanas.push({
        ref: `${registro_ente}:${registro_id}`,
        etiqueta: datos.sobre.etiqueta,
        ficha: <Fragment key={`${accion.vincular}:${accion.estado}`}>{tab}</Fragment>,
      });
    const refs = [...(abierto.descripcion ?? "").matchAll(REFERENCIA)]
      .map(([, ente, rid, nombre]) => ({ ref: `${ente}:${rid}`, ente, rid, nombre }))
      .filter((r, i, todas) => r.ref in datos.enlaces && todas.findIndex((o) => o.ref === r.ref) === i)
      .filter((r) => !pestanas.some((p) => p.ref === r.ref));
    const fichas = await Promise.all(refs.map((r) => ficha(r.ente, r.rid)));
    refs.forEach((r, i) => {
      if (fichas[i]) pestanas.push({ ref: r.ref, etiqueta: r.nombre, ficha: fichas[i] });
    });
  }

  const vista = (
    <HiloView
      {...datos}
      pasoAbierto={abierto?.id ?? null}
      pestanas={pestanas}
      plantillas={plantillas.filter((p) => p.activo && p.dueno_id === contexto.yo)}
      ctx={{ ...contexto, asignables, admin, pedir, delegador }}
    />
  );
  // Al lado, solo la ficha del registro del hilo (registro.md); sin ella, a todo el ancho.
  if (!registro) return vista;
  return (
    <div className="grid items-start gap-6 lg:grid-cols-2">
      {vista}
      <section aria-label="Ficha del registro">{registro}</section>
    </div>
  );
}
