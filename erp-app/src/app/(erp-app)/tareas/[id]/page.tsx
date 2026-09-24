import { notFound } from "next/navigation";
import { idSchema } from "@/modules/tareas/types";
import { puedeAdministrar, puedePedir, puedeVerEquipo, puedeVerTareas } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getHilo } from "@/modules/tareas/queries";
import { HiloView } from "@/modules/tareas/components/HiloView";

export default async function HiloPage(props: PageProps<"/tareas/[id]">) {
  const { id } = await props.params;
  const { paso } = await props.searchParams;
  if (!(await puedeVerTareas()) || !idSchema.safeParse(id).success) notFound();

  const [datos, contexto, asignables, admin, pedir, delegador] = await Promise.all([
    getHilo(id),
    getContexto(),
    getAsignables(),
    puedeAdministrar(),
    puedePedir(),
    puedeVerEquipo(),
  ]);
  if (!datos) notFound();

  return (
    <HiloView
      {...datos}
      pasoAbierto={typeof paso === "string" ? paso : null}
      ctx={{ ...contexto, asignables, admin, pedir, delegador }}
    />
  );
}
