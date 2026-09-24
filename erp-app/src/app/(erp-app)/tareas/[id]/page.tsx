import { notFound } from "next/navigation";
import { idSchema } from "@/modules/tareas/types";
import { puedeAdministrar, puedePedir, puedeVerEquipo, puedeVerPlantillas, puedeVerTareas } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getHilo, getPlantillas } from "@/modules/tareas/queries";
import { HiloView } from "@/modules/tareas/components/HiloView";

export default async function HiloPage(props: PageProps<"/tareas/[id]">) {
  const { id } = await props.params;
  const { paso } = await props.searchParams;
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

  return (
    <HiloView
      {...datos}
      pasoAbierto={typeof paso === "string" ? paso : null}
      plantillas={plantillas.filter((p) => p.activo && p.dueno_id === contexto.yo)}
      ctx={{ ...contexto, asignables, admin, pedir, delegador }}
    />
  );
}
