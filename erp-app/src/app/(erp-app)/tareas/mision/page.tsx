import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeVerMision } from "@/modules/tareas/permissions";
import { getMision } from "@/modules/tareas/queries";
import { MisionView } from "@/modules/tareas/components/MisionView";

export default async function MisionPage() {
  if (!(await puedeVerMision())) notFound();

  const yo = await getUsuarioActualId();
  if (!yo) notFound();
  const { pasos, cadena, enlaces } = await getMision(yo);

  return <MisionView pasos={pasos} cadena={cadena} enlaces={enlaces} />;
}
