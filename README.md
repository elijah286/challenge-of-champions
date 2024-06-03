# challenge-of-champions

This software was developed by Elijah Kerry for the 2024 NI Connect Challenge of the Champions.

Installation 
- Install LabVIEW 2024 or later
- Run the VIPC file to install the necessary dependencies
- Connect an external display and ensure the OS displays settings are set to 'extend' NOT 'mirror'
- Run main.vi

Configuration
- Select the 4 channels on the connected DAQ device
- Select 'test buzzers' to ensure the buzzer presses are registering correctly
- Replace 'Contestant 1...4' with the names and press 'reset contestant names and scores
- Select 'instructions' to review the rules
- Change the 'Sound ID' until audio is output. If this doesn't work after plugging in external audio, you may need to restart LabVIEW

Key Features:
- Large, resizeable grid for selecting questions
- Uses NI DAQ to acquire points
- Capable of displaying text and images for the prompt
- Has a separate panel for the MC to make facilitation easy

Game Rules:
- Contestants may buzz in as soon as the question is selelected
- Once they buzz in, they ahve limited time to answer the question
- If correct, the points are added to the score
- If incorrect, points are subtracted

Implementation
This software is written using actor framework and extensively relies on subpanels for the displays and the questions.
