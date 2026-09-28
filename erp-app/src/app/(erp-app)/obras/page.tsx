import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAprobar, puedeCrear, puedeVerObras } from "@/modules/obras/permissions";
import { getNombres, getObras, getPorAprobar } from "@/modules/obras/queries";
import { Obras } from "./Obras";

export default async function ObrasPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerObras())) notFound();

  const [obras, nombres, crear, aprobar] = await Promise.all([
    getObras({ inactivas: false }),
    getNombres(),
    puedeCrear(),
    puedeAprobar(),
  ]);
  const porAprobar = aprobar ? (await getPorAprobar()).length : undefined;

  return <Obras obras={obras} yo={yo} nombres={nombres} puedeCrear={crear} porAprobar={porAprobar} />;
}
