document.getElementById('loginForm').addEventListener('submit', async function (event) {
    event.preventDefault();

    const errorMessage = document.getElementById('errorMessage');
    errorMessage.style.display = 'none';
    errorMessage.textContent = '';

    const data = {
        username: document.getElementById('username').value.trim(),
        password: document.getElementById('password').value
    };

    try {
        const response = await fetch('/api/v1/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (!response.ok || !result.success) {
            errorMessage.style.display = 'block';
            errorMessage.textContent = result.error || 'Authentication failed';
            return;
        }

        const token = result.data.token;
        sessionStorage.setItem('token', token);
        window.location.href = '/dashboard';
    } catch (error) {
        errorMessage.style.display = 'block';
        errorMessage.textContent = 'Connection error to server';
    }
});