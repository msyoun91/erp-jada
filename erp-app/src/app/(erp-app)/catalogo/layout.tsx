import { Modulo } from "@/components/layout/Modulo";
import { pestanasCatalogo } from "@/modules/catalogo/pestanas";

export default async function CatalogoLayout({ children }: { children: React.ReactNode }) {
  const tabs = await pestanasCatalogo();

  return (
    <Modulo modulo="catalogo" tabs={tabs}>
      {children}
    </Modulo>
  );
}
