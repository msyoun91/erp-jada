import { notFound } from "next/navigation";
import { idSchema } from "@/modules/tareas/types";
import { puedeVerTodas } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getTodas } from "@/modules/tareas/queries";
import { TodasView } from "@/modules/tareas/components/TodasView";

export default async function TodasPage(props: PageProps<"/tareas/todas">) {
  if (!(await puedeVerTodas())) notFound();
  const { responsable } = await props.searchParams;

  const [contexto, asignables, hilos] = await Promise.all([getContexto(), getAsignables(), getTodas()]);

  return (
    <TodasView
      hilos={hilos}
      yo={contexto.yo}
      nombres={contexto.nombres}
      asignables={asignables}
      responsable={idSchema.safeParse(responsable).success ? (responsable as string) : null}
    />
  );
}
