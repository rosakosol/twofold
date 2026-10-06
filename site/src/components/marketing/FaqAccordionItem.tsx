import { AccordionItem } from "@/components/site/Accordion";

/** One FAQ question and its answer, as the shared native accordion (src/components/site/Accordion).
 *  The answer is the live copy as written in the Studio. */
export function FaqAccordionItem({
  question,
  answer,
  defaultOpen = false,
}: {
  question: string;
  answer: string;
  defaultOpen?: boolean;
}) {
  return (
    <AccordionItem title={question} defaultOpen={defaultOpen}>
      <p>{answer}</p>
    </AccordionItem>
  );
}
