import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAprobar, puedeCrear, puedeVerObras } from "@/modules/obras/permissions";
import { getNombres, getObras, getPorAprobar } from "@/modules/obras/queries";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getEnCotizacionDeContratadas } from "@/modules/presupuestos/queries";
import { Obras } from "./Obras";

export default async function ObrasPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerObras())) notFound();

  const [obras, nombres, crear, aprobar, enCotizacion] = await Promise.all([
    getObras({ inactivas: false }),
    getNombres(),
    puedeCrear(),
    puedeAprobar(),
    puedeVerPresupuestos().then((ve) => (ve ? getEnCotizacionDeContratadas() : undefined)),
  ]);
  const porAprobar = aprobar ? (await getPorAprobar()).length : undefined;

  return (
    <Obras obras={obras} yo={yo} nombres={nombres} puedeCrear={crear} porAprobar={porAprobar} enCotizacion={enCotizacion} />
  );
}
