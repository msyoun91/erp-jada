import { notFound } from "next/navigation";
import { puedeCorregir, puedeElegirPrincipal, puedeVerMonedas } from "@/modules/monedas/permissions";
import { getAvisos, getHistorial, getPrincipal, getTiposCambioHoy } from "@/modules/monedas/queries";
import { MonedasView } from "@/modules/monedas/components/MonedasView";

export default async function MonedasPage() {
  if (!(await puedeVerMonedas())) notFound();

  const [hoy, avisos, principal, corregir, elegirPrincipal] = await Promise.all([
    getTiposCambioHoy(),
    getAvisos(),
    getPrincipal(),
    puedeCorregir(),
    puedeElegirPrincipal(),
  ]);
  const historiales = await Promise.all(hoy.map((t) => getHistorial(t.moneda)));

  return (
    <MonedasView
      monedas={hoy.map((t, i) => ({ ...t, historial: historiales[i] }))}
      avisos={avisos}
      principal={principal}
      puedeCorregir={corregir}
      puedeElegirPrincipal={elegirPrincipal}
    />
  );
}
