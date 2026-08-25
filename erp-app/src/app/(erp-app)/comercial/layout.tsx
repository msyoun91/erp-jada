import { Target } from "lucide-react";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import {
  puedeVerEmpresas,
  puedeVerObras,
  puedeVerPersonas,
  puedeVerProspectos,
} from "@/modules/comercial/permissions";

export default async function ComercialLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [prospectos, obras, empresas, personas] = await Promise.all([
    puedeVerProspectos(),
    puedeVerObras(),
    puedeVerEmpresas(),
    puedeVerPersonas(),
  ]);

  const tabs = [
    prospectos && { codigo: "comercial_prospectos", label: "Prospectos", href: "/comercial" },
    obras && { codigo: "comercial_obras", label: "Obras", href: "/comercial/obras" },
    empresas && { codigo: "comercial_empresas", label: "Empresas", href: "/comercial/empresas" },
    personas && { codigo: "comercial_personas", label: "Personas", href: "/comercial/personas" },
  ].filter((t): t is { codigo: string; label: string; href: string } => Boolean(t));

  return (
    <div className="flex h-full flex-col">
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <Target size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Comercial
      </h1>
      <ModuleTabs modulo="comercial" tabs={tabs} />
      {children}
    </div>
  );
}
