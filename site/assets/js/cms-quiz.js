// Twofold — relationship quiz on the home page, between the feature grid and the
// pricing teaser. Fetches questions + the two possible results from Sanity; if there
// are no published questions, the whole `#quiz` section stays hidden (its default state
// in the HTML) and nothing else here runs.
//
// Scoring: each answer's `lean` maps to a fixed weight (see LEAN_WEIGHTS). Summing the
// weights of all answered questions and checking the sign keeps the recommendation
// logic simple and bounded regardless of how an editor rewrites question/answer copy in
// the Studio — see quizQuestion.ts for why the weight scale itself isn't editable.

import { sanityFetch } from "/assets/js/cms.js";

const LEAN_WEIGHTS = {
  strong_plus: -2,
  plus: -1,
  neutral: 0,
  premium: 1,
  strong_premium: 2,
};

const FALLBACK_RESULTS = {
  plus: { title: "Twofold Plus is right for you", description: "Everything you need for long-distance love.", ctaLabel: "Get Twofold Plus" },
  premium: { title: "Twofold Premium is right for you", description: "The full relationship globe experience.", ctaLabel: "Get Twofold Premium" },
};

const els = {
  section: document.getElementById("quiz"),
  questionCard: document.getElementById("quiz-question-card"),
  resultCard: document.getElementById("quiz-result-card"),
  progress: document.getElementById("quiz-progress"),
  questionText: document.getElementById("quiz-question-text"),
  options: document.getElementById("quiz-options"),
  backBtn: document.getElementById("quiz-back"),
  resultTitle: document.getElementById("quiz-result-title"),
  resultDescription: document.getElementById("quiz-result-description"),
  resultCta: document.getElementById("quiz-result-cta"),
  retakeBtn: document.getElementById("quiz-retake"),
};

let questions = [];
let results = { plus: FALLBACK_RESULTS.plus, premium: FALLBACK_RESULTS.premium };
let answers = [];
let currentIndex = 0;

function renderProgress() {
  els.progress.innerHTML = "";
  questions.forEach((_, i) => {
    const dot = document.createElement("span");
    dot.className = "dot";
    if (i < currentIndex) dot.classList.add("is-done");
    if (i === currentIndex) dot.classList.add("is-current");
    els.progress.appendChild(dot);
  });
}

function renderQuestion() {
  const question = questions[currentIndex];
  renderProgress();
  els.questionText.textContent = question.question;
  els.backBtn.disabled = currentIndex === 0;

  els.options.innerHTML = "";
  (question.options ?? []).forEach((option) => {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "quiz-option";
    if (answers[currentIndex] === option.lean) btn.classList.add("is-selected");
    btn.textContent = option.label;
    btn.addEventListener("click", () => selectAnswer(option.lean));
    els.options.appendChild(btn);
  });
}

function selectAnswer(lean) {
  answers[currentIndex] = lean;
  if (currentIndex < questions.length - 1) {
    currentIndex += 1;
    renderQuestion();
  } else {
    showResult();
  }
}

function showResult() {
  const score = answers.reduce((sum, lean) => sum + (LEAN_WEIGHTS[lean] ?? 0), 0);
  const plan = score > 0 ? "premium" : "plus";
  const result = results[plan];

  els.resultTitle.textContent = result.title;
  els.resultDescription.textContent = result.description;
  els.resultCta.textContent = result.ctaLabel;
  // The quiz lives on the home page, the plan tabs live on /pricing.html — hand off via
  // a query param rather than a same-page DOM click. pricing.js reads `?plan=` on load
  // and pre-selects that tab (see PLAN_PARAM handling there).
  els.resultCta.href = `/pricing.html?plan=${plan}`;

  els.questionCard.hidden = true;
  els.resultCard.hidden = false;
  els.resultCard.scrollIntoView({ behavior: "smooth", block: "start" });
}

function retake() {
  answers = new Array(questions.length).fill(null);
  currentIndex = 0;
  els.resultCard.hidden = true;
  els.questionCard.hidden = false;
  renderQuestion();
}

els.backBtn?.addEventListener("click", () => {
  if (currentIndex > 0) {
    currentIndex -= 1;
    renderQuestion();
  }
});

els.retakeBtn?.addEventListener("click", retake);

async function init() {
  if (!els.section) return;

  const data = await sanityFetch(`{
    "questions": *[_type == "quizQuestion"] | order(order asc){question, options},
    "resultPlus": *[_id == "quizResult-plus"][0]{title, description, ctaLabel},
    "resultPremium": *[_id == "quizResult-premium"][0]{title, description, ctaLabel}
  }`);

  questions = (data?.questions ?? []).filter((q) => q.question && (q.options ?? []).length >= 2);
  if (!questions.length) return; // section stays hidden — its default state

  if (data.resultPlus?.title) results.plus = data.resultPlus;
  if (data.resultPremium?.title) results.premium = data.resultPremium;

  answers = new Array(questions.length).fill(null);
  els.section.hidden = false;
  els.questionCard.hidden = false;
  renderQuestion();
}

init();
