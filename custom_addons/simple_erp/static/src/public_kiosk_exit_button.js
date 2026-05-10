/** @odoo-module **/

function ensureExitButton() {
    if (document.querySelector(".o_simple_erp_kiosk_exit_button")) {
        return;
    }

    const kioskRoot = document.querySelector(".o_hr_attendance_kiosk_mode") || document.body;
    if (!kioskRoot) {
        return;
    }

    const button = document.createElement("a");
    button.className = "o_simple_erp_kiosk_exit_button btn btn-light btn-lg rounded-pill shadow";
    button.href = "/web";
    button.textContent = "Exit Kiosk";
    button.setAttribute("aria-label", "Exit kiosk");

    kioskRoot.appendChild(button);
}

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ensureExitButton, { once: true });
} else {
    ensureExitButton();
}
