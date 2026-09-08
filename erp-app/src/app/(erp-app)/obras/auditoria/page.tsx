import { notFound } from "next/navigation";
import { DIAS_OPCIONES } from "@/components/ui/FiltroDias";
import { puedeVerAuditoria } from "@/modules/obras/permissions";
import { getAuditoriaAccesos, getAuditoriaTransferencias } from "@/modules/obras/queries";
import { AuditoriaView } from "@/modules/obras/components/AuditoriaView";

export default async function ObrasAuditoriaPage({
  searchParams,
}: {
  searchParams: Promise<{ dias?: string }>;
}) {
  if (!(await puedeVerAuditoria())) notFound();

  const { dias: diasParam } = await searchParams;
  const pedido = Number(diasParam);
  const dias = DIAS_OPCIONES.includes(pedido) ? pedido : 30;

  const [accesos, transferencias] = await Promise.all([
    getAuditoriaAccesos(dias),
    getAuditoriaTransferencias(dias),
  ]);

  return <AuditoriaView accesos={accesos} transferencias={transferencias} dias={dias} />;
}
