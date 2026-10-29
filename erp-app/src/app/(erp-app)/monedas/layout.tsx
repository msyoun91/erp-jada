import { Coins } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import { puedeVerMonedas } from "@/modules/monedas/permissions";

export default async function MonedasLayout({ children }: { children: React.ReactNode }) {
  const tabs = (await puedeVerMonedas()) ? [{ codigo: "monedas_ver", label: "Monedas", href: "/monedas" }] : [];

  return (
    <div className="flex flex-col h-full">
      <Breadcrumb modulo="monedas" tabs={tabs} />
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <Coins size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Monedas
      </h1>
      <ModuleTabs modulo="monedas" tabs={tabs} />
      {children}
    </div>
  );
}
