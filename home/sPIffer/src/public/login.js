document.getElementById('loginForm').addEventListener('submit', async function(event) {
    event.preventDefault();
    const formData = new FormData(this);
    const data = new URLSearchParams(formData);
    try {
        const response = await fetch('/login', {
            method: 'POST',
            body: data,
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded'
            }
        });
        if (!response.ok) {
            const errorData = await response.json();
            document.getElementById('errorMessage').style.display = 'block';
            document.getElementById('errorMessage').textContent = errorData.error;
        } else {
            window.location.href = '/dashboard'; // Redirige en cas de succès
        }
    } catch (error) {
        document.getElementById('errorMessage').textContent = "Connection error to server";
    }
});