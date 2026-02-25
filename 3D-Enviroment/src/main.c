#include "config.h"
#include "raycaster.h"
#include "player.h"

const short MAP[MAP_GRID_HEIGHT][MAP_GRID_WIDTH] = {
    {R,R,R,R,R,R,R,R,R,R},
    {R,R,0,R,0,0,P,0,R,R},
    {R,0,0,R,0,0,0,0,0,R},
    {R,0,0,R,R,R,R,0,0,R},
    {R,0,0,0,0,0,0,0,0,R},
    {R,0,0,0,0,0,0,0,0,R},
    {R,0,0,R,0,0,R,R,R,R},
    {R,0,0,0,0,0,0,0,0,R},
    {R,R,0,0,0,0,0,0,R,R},
    {R,R,R,R,R,R,R,R,R,R}
};


/* Program toggles */
char gameIsRunning    = TRUE;

void readInputs(){
    return;
}

void main() {
    initPlayer();
    while(1) {

        // character presses
        readInputs();

        /* Update the player */
        updatePlayer();

        /* Update the raycaster */
        updateRaycaster();

    } 
}