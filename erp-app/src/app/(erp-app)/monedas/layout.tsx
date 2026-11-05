import { Modulo } from "@/components/layout/Modulo";
import { puedeVerMonedas } from "@/modules/monedas/permissions";

export default async function MonedasLayout({ children }: { children: React.ReactNode }) {
  const tabs = (await puedeVerMonedas()) ? [{ codigo: "monedas_ver", label: "Monedas", href: "/monedas" }] : [];

  return (
    <Modulo modulo="monedas" tabs={tabs}>
      {children}
    </Modulo>
  );
}
