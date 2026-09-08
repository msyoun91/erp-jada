import { Building2 } from "lucide-react";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import {
  puedeVerAuditoria,
  puedeVerEmpresas,
  puedeVerObras,
  puedeVerPendientes,
  puedeVerPersonas,
} from "@/modules/obras/permissions";

export default async function ObrasLayout({ children }: { children: React.ReactNode }) {
  const [obras, empresas, personas, pendientes, auditoria] = await Promise.all([
    puedeVerObras(),
    puedeVerEmpresas(),
    puedeVerPersonas(),
    puedeVerPendientes(),
    puedeVerAuditoria(),
  ]);

  const tabs = [
    obras && { codigo: "obras_ver", label: "Obras", href: "/obras" },
    empresas && { codigo: "obras_empresas", label: "Empresas", href: "/obras/empresas" },
    personas && { codigo: "obras_personas", label: "Personas", href: "/obras/personas" },
    pendientes && { codigo: "obras_pendientes", label: "Pendientes", href: "/obras/pendientes" },
    auditoria && { codigo: "obras_auditoria", label: "Auditoría", href: "/obras/auditoria" },
  ].filter((t): t is { codigo: string; label: string; href: string } => Boolean(t));

  return (
    <div className="flex h-full flex-col">
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <Building2 size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Agenda de Obras
      </h1>
      <ModuleTabs modulo="obras" tabs={tabs} />
      {children}
    </div>
  );
}
