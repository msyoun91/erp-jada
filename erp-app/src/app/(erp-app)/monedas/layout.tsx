import { Modulo } from "@/components/layout/Modulo";
import { getTutorialVistos } from "@/lib/tutorial";
import { TUTORIAL_MONEDAS } from "@/modules/monedas/tutorial";
import { puedeVerMonedas } from "@/modules/monedas/permissions";

export default async function MonedasLayout({ children }: { children: React.ReactNode }) {
  const tabs = (await puedeVerMonedas()) ? [{ codigo: "monedas_ver", label: "Monedas", href: "/monedas" }] : [];

  return (
    <Modulo modulo="monedas" tabs={tabs} tutorial={{ guion: TUTORIAL_MONEDAS, vistos: await getTutorialVistos() }}>
      {children}
    </Modulo>
  );
}
