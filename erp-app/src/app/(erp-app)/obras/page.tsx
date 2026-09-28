import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeCrear, puedeVerObras } from "@/modules/obras/permissions";
import { getNombres, getObras } from "@/modules/obras/queries";
import { Obras } from "./Obras";

export default async function ObrasPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerObras())) notFound();

  const [obras, nombres, crear] = await Promise.all([getObras({ inactivas: false }), getNombres(), puedeCrear()]);

  return <Obras obras={obras} yo={yo} nombres={nombres} puedeCrear={crear} />;
}
