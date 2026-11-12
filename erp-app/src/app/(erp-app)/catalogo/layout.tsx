import { Modulo } from "@/components/layout/Modulo";
import { getTutorialVistos } from "@/lib/tutorial";
import { TUTORIAL_CATALOGO } from "@/modules/catalogo/tutorial";
import { pestanasCatalogo } from "@/modules/catalogo/pestanas";

export default async function CatalogoLayout({ children }: { children: React.ReactNode }) {
  const tabs = await pestanasCatalogo();

  return (
    <Modulo modulo="catalogo" tabs={tabs} tutorial={{ guion: TUTORIAL_CATALOGO, vistos: await getTutorialVistos() }}>
      {children}
    </Modulo>
  );
}
