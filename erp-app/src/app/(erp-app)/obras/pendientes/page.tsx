import { notFound } from "next/navigation";
import { puedeAprobar, puedeVerPendientes } from "@/modules/obras/permissions";
import { getHistorialAprobaciones, getPendientes } from "@/modules/obras/queries";
import { PendientesView } from "@/modules/obras/components/PendientesView";

const DIAS_VALIDOS = [7, 30, 90];

export default async function ObrasPendientesPage({
  searchParams,
}: {
  searchParams: Promise<{ dias?: string }>;
}) {
  if (!(await puedeVerPendientes())) notFound();

  const { dias: diasParam } = await searchParams;
  const pedido = Number(diasParam);
  const dias = DIAS_VALIDOS.includes(pedido) ? pedido : 30;

  const [pendientes, historial, aprobar] = await Promise.all([
    getPendientes(),
    getHistorialAprobaciones(dias),
    puedeAprobar(),
  ]);

  return (
    <PendientesView
      pendientes={pendientes}
      historial={historial}
      dias={dias}
      puedeAprobar={aprobar}
    />
  );
}
