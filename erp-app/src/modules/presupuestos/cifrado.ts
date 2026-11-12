import { createCipheriv, createHash, randomBytes } from "node:crypto";

// Del link salen dos cosas que el portal no puede cruzar: la huella, que guarda su base, y la llave, que nunca sale del
// navegador. Los prefijos las separan. El navegador hace lo mismo con WebCrypto (decisiones/erp-cliente.md → Dos bases).
const sha256 = (texto: string) => createHash("sha256").update(texto, "utf8").digest();

export function huellaDe(link: string): string {
  return sha256(`huella:${link}`).toString("hex");
}

// AES-256-GCM, base64 de iv (12) ‖ cifrado ‖ tag (16): el orden que WebCrypto espera al descifrar.
export function cifrar(link: string, texto: string): string {
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", sha256(`llave:${link}`), iv);
  return Buffer.concat([iv, c.update(texto, "utf8"), c.final(), c.getAuthTag()]).toString("base64");
}
