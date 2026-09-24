import { notFound, redirect } from "next/navigation";
import { idSchema } from "@/modules/tareas/types";
import { puedeVerTareas } from "@/modules/tareas/permissions";
import { getHiloDePaso } from "@/modules/tareas/queries";

// La ruta del ente `tarea`: abre su hilo en ese paso.
export default async function PasoPage(props: PageProps<"/tareas/paso/[id]">) {
  const { id } = await props.params;
  if (!(await puedeVerTareas()) || !idSchema.safeParse(id).success) notFound();

  const hilo = await getHiloDePaso(id);
  if (!hilo) notFound();
  redirect(`/tareas/${hilo}?paso=${id}`);
}
