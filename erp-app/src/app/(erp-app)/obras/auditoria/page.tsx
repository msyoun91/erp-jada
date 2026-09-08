import { notFound } from "next/navigation";
import { puedeVerAuditoria } from "@/modules/obras/permissions";
import { getAuditoriaAccesos, getAuditoriaTransferencias } from "@/modules/obras/queries";
import { AuditoriaView } from "@/modules/obras/components/AuditoriaView";

const DIAS_VALIDOS = [7, 30, 90];

export default async function ObrasAuditoriaPage({
  searchParams,
}: {
  searchParams: Promise<{ dias?: string }>;
}) {
  if (!(await puedeVerAuditoria())) notFound();

  const { dias: diasParam } = await searchParams;
  const pedido = Number(diasParam);
  const dias = DIAS_VALIDOS.includes(pedido) ? pedido : 30;

  const [accesos, transferencias] = await Promise.all([
    getAuditoriaAccesos(dias),
    getAuditoriaTransferencias(dias),
  ]);

  return <AuditoriaView accesos={accesos} transferencias={transferencias} dias={dias} />;
}
