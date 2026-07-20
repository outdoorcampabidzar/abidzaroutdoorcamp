import { supabase, esc, message } from "./app.js";

let summary = {
  rating_average: 0,
  rating_count: 0,
  my_score: 0,
  my_comment: "",
};

let hoverScore = 0;
let isSaving = false;
let reviewLimit = 6;
let allReviewCount = 0;

function staticStars(value = 0) {
  const rounded = Math.round(Number(value || 0));

  return [1, 2, 3, 4, 5]
    .map(
      (score) => `
      <span class="${score <= rounded ? "filled" : ""}" aria-hidden="true">
        ★
      </span>
    `,
    )
    .join("");
}

function interactiveStars() {
  return [1, 2, 3, 4, 5]
    .map(
      (score) => `
      <button
        class="website-rating-star"
        type="button"
        data-website-score="${score}"
        aria-label="Beri rating website ${score} bintang"
        aria-pressed="false"
      >
        ★
      </button>
    `,
    )
    .join("");
}

function ratingElements() {
  return {
    form: document.getElementById("websiteRatingForm"),
    stars: document.getElementById("websiteRatingStaticStars"),
    average: document.getElementById("websiteRatingAverage"),
    count: document.getElementById("websiteRatingCount"),
    buttons: document.getElementById("websiteRatingStars"),
    scoreInput: document.getElementById("websiteRatingScore"),
    comment: document.getElementById("websiteRatingComment"),
    submitButton: document.getElementById("websiteRatingSubmit"),
    helper: document.getElementById("websiteRatingHelper"),
    messageBox: document.getElementById("websiteRatingMessage"),
    reviewsList: document.getElementById("websiteReviewsList"),
    reviewsCount: document.getElementById("websiteReviewCount"),
    reviewsMore: document.getElementById("websiteReviewsLoadMore"),
  };
}

function paintSelectedStars(score = 0) {
  const selectedScore = Number(score || 0);

  document.querySelectorAll("[data-website-score]").forEach((button) => {
    const buttonScore = Number(button.dataset.websiteScore);
    const active = buttonScore <= selectedScore;
    const exact = buttonScore === Number(summary.my_score || 0);

    button.classList.toggle("active", active);
    button.setAttribute("aria-pressed", String(exact));
  });
}

function clearMessage() {
  const { messageBox } = ratingElements();

  if (!messageBox) return;

  messageBox.textContent = "";
  messageBox.className = "notice hidden";
}

function updateInterface() {
  const {
    stars,
    average,
    count,
    buttons,
    scoreInput,
    comment,
    submitButton,
    helper,
  } = ratingElements();

  if (stars) {
    stars.innerHTML = staticStars(summary.rating_average);
  }

  if (average) {
    average.textContent = Number(summary.rating_average || 0).toFixed(1);
  }

  if (count) {
    count.textContent = `${Number(summary.rating_count || 0)} penilaian`;
  }

  if (buttons && !buttons.dataset.initialized) {
    buttons.innerHTML = interactiveStars();
    buttons.dataset.initialized = "true";
    bindStarButtons();
  }

  if (scoreInput) {
    scoreInput.value = String(Number(summary.my_score || 0));
  }

  hoverScore = 0;
  paintSelectedStars(summary.my_score);

  if (helper) {
    helper.textContent = summary.my_score
      ? `Rating dipilih: ${summary.my_score} bintang. Klik bintang lain untuk mengubah.`
      : "Pilih 1–5 bintang untuk menilai website ini.";
  }

  if (comment && document.activeElement !== comment) {
    comment.value = summary.my_comment || "";
  }

  if (submitButton) {
    submitButton.disabled = isSaving;
    submitButton.textContent = isSaving
      ? "Mengirim Rating..."
      : summary.my_score
        ? "Simpan Rating Website"
        : "Kirim Rating";
  }
}

function selectRating(score) {
  summary.my_score = Number(score);
  hoverScore = 0;

  const { scoreInput } = ratingElements();

  if (scoreInput) {
    scoreInput.value = String(summary.my_score);
  }

  paintSelectedStars(summary.my_score);
  updateInterface();
  clearMessage();
}

function bindStarButtons() {
  const { buttons } = ratingElements();

  if (!buttons || buttons.dataset.bound === "true") return;

  buttons.dataset.bound = "true";

  buttons.addEventListener("mouseover", (event) => {
    const button = event.target.closest("[data-website-score]");
    if (!button || !buttons.contains(button)) return;

    hoverScore = Number(button.dataset.websiteScore);
    paintSelectedStars(hoverScore);
  });

  buttons.addEventListener("mouseleave", () => {
    hoverScore = 0;
    paintSelectedStars(summary.my_score);
  });

  buttons.addEventListener("focusin", (event) => {
    const button = event.target.closest("[data-website-score]");
    if (!button || !buttons.contains(button)) return;

    hoverScore = Number(button.dataset.websiteScore);
    paintSelectedStars(hoverScore);
  });

  buttons.addEventListener("focusout", (event) => {
    if (buttons.contains(event.relatedTarget)) return;

    hoverScore = 0;
    paintSelectedStars(summary.my_score);
  });

  buttons.addEventListener("click", (event) => {
    const button = event.target.closest("[data-website-score]");
    if (!button || !buttons.contains(button)) return;

    event.preventDefault();
    selectRating(Number(button.dataset.websiteScore));
  });
}

function reviewCard(review) {
  const displayName = review.display_name || "Pengguna";
  const date = new Date(review.updated_at || review.created_at);

  return `
    <article class="card website-review-card">
      <div class="website-review-top">
        <div class="website-review-avatar" aria-hidden="true">
          ${esc(displayName.slice(0, 1).toUpperCase())}
        </div>

        <div class="website-review-user">
          <div>
            <strong>${esc(displayName)}</strong>
            ${review.is_mine ? '<span class="website-review-mine">Ulasan Anda</span>' : ""}
          </div>
          <small>${date.toLocaleDateString("id-ID", { dateStyle: "medium" })}</small>
        </div>

        <div
          class="website-review-stars"
          aria-label="${Number(review.score)} dari 5 bintang"
        >
          ${staticStars(review.score)}
        </div>
      </div>

      <p>${esc(review.comment)}</p>
    </article>
  `;
}

async function loadReviews() {
  const { reviewsList, reviewsCount, reviewsMore } = ratingElements();

  if (!reviewsList) return;

  try {
    const { data, error } = await supabase.rpc("get_website_reviews", {
      p_limit: reviewLimit,
    });

    if (error) throw error;

    const reviews = data || [];
    allReviewCount = Number(reviews[0]?.total_count || 0);

    if (reviewsCount) {
      reviewsCount.textContent = `${allReviewCount} komentar`;
      reviewsCount.classList.toggle("hidden", allReviewCount === 0);
    }

    if (!reviews.length) {
      reviewsList.innerHTML = `
        <div class="notice">
          Belum ada komentar. Jadilah pengguna pertama yang memberikan ulasan.
        </div>
      `;
    } else {
      reviewsList.innerHTML = reviews.map(reviewCard).join("");
    }

    if (reviewsMore) {
      reviewsMore.classList.toggle("hidden", reviews.length >= allReviewCount);
    }
  } catch (error) {
    reviewsList.innerHTML = `
      <div class="notice error">
        Komentar belum dapat dimuat: ${esc(error.message)}
      </div>
    `;
  }
}

async function loadWebsiteRating() {
  const { messageBox } = ratingElements();

  try {
    const { data, error } = await supabase.rpc("get_website_rating");

    if (error) throw error;

    summary = {
      rating_average: Number(data?.rating_average || 0),
      rating_count: Number(data?.rating_count || 0),
      my_score: Number(data?.my_score || 0),
      my_comment: data?.my_comment || "",
    };

    updateInterface();
  } catch (error) {
    message(
      messageBox,
      `Rating website belum dapat dimuat: ${error.message}`,
      "error",
    );
  }
}

async function saveWebsiteRating() {
  const { comment, scoreInput, submitButton, messageBox } = ratingElements();

  if (isSaving) return;

  const selectedScore = Number(scoreInput?.value || summary.my_score || 0);

  if (!selectedScore || selectedScore < 1 || selectedScore > 5) {
    message(messageBox, "Pilih jumlah bintang terlebih dahulu.", "error");
    return;
  }

  try {
    const {
      data: { session },
      error: sessionError,
    } = await supabase.auth.getSession();

    if (sessionError) throw sessionError;

    if (!session?.user) {
      const next = encodeURIComponent("index.html#website-rating");
      location.href = `login.html?next=${next}`;
      return;
    }

    isSaving = true;
    summary.my_score = selectedScore;
    updateInterface();

    document.querySelectorAll("[data-website-score]").forEach((button) => {
      button.disabled = true;
    });

    message(
      messageBox,
      "Sedang menyimpan rating dan komentar ke database...",
      "warning",
    );

    const typedComment = String(comment?.value || "")
      .trim()
      .slice(0, 300);

    // Kolom kosong mempertahankan komentar lama.
    const commentValue = typedComment || summary.my_comment || "";

    const { data, error } = await supabase.rpc("save_website_review_v2", {
      p_payload: {
        score: selectedScore,
        comment: commentValue,
      },
    });

    if (error) throw error;

    const savedComment = String(data?.my_comment || "");

    // Pastikan komentar yang diketik benar-benar kembali dari database.
    if (typedComment && savedComment.trim() !== typedComment.trim()) {
      throw new Error(
        "Rating tersimpan, tetapi komentar tidak kembali dari database. " +
          "Pastikan website-comment-rpc-v2.sql sudah dijalankan.",
      );
    }

    summary = {
      rating_average: Number(data?.rating_average || 0),
      rating_count: Number(data?.rating_count || 0),
      my_score: Number(data?.my_score || selectedScore),
      my_comment: savedComment || commentValue,
    };

    updateInterface();
    await loadReviews();

    message(
      messageBox,
      summary.my_comment
        ? `Berhasil! Rating dan komentar Anda sudah ditampilkan.`
        : `Berhasil! Rating ${summary.my_score} bintang sudah tersimpan.`,
      "success",
    );
  } catch (error) {
    message(messageBox, `Rating gagal dikirim: ${error.message}`, "error");
  } finally {
    isSaving = false;

    document.querySelectorAll("[data-website-score]").forEach((button) => {
      button.disabled = false;
    });

    updateInterface();
    submitButton?.blur();
  }
}

export function mountWebsiteRating() {
  const { form, submitButton, reviewsMore } = ratingElements();

  if (!form || !submitButton) return;

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    saveWebsiteRating();
  });

  submitButton.addEventListener("click", (event) => {
    event.preventDefault();
    saveWebsiteRating();
  });

  reviewsMore?.addEventListener("click", () => {
    reviewLimit += 6;
    loadReviews();
  });

  updateInterface();
  loadWebsiteRating();
  loadReviews();
}
